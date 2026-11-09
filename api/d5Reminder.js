'use strict';

// D5: automated due-date reminder. Task dates in this project are stored as
// YYYY-MM-DD at 00:00 UTC, so the window is based on that stored timestamp.
// No sending occurs until D5_REMINDER_MODE=send is explicitly configured.

const Task = require('./models/Task');
const User = require('./models/User');
const EmailLog = require('./models/EmailLog');
const { smtpConfig, isTestEmail } = require('./d1Email');

const EVENT_TYPE = 'task_due_reminder';
const SUBJECT = 'TaskManager - Nhắc công việc sắp đến hạn';

function positiveInteger(value, fallback, maximum) {
  const n = Number(value);
  return Number.isInteger(n) && n >= 1 && n <= maximum ? n : fallback;
}

function reminderHours(env = process.env) {
  return positiveInteger(env.D5_REMINDER_HOURS, 24, 168);
}

function reminderIntervalMinutes(env = process.env) {
  return positiveInteger(env.D5_REMINDER_INTERVAL_MINUTES, 5, 1440);
}

function isDueSoon(task, now = new Date(), hours = 24) {
  if (!task || task.status === 'completed' || !task.dueDate) return false;
  const due = new Date(task.dueDate).getTime();
  const current = new Date(now).getTime();
  return Number.isFinite(due) && Number.isFinite(current) &&
    due >= current && due <= current + hours * 60 * 60 * 1000;
}

function uniqueRecipientIds(task) {
  return [...new Set([task.createdBy, ...(task.assigneeIds || [])]
    .filter(Boolean).map(String))];
}

function reminderEmailText(task, hours) {
  const deadline = new Date(task.dueDate).toISOString().slice(0, 10);
  return [
    `Công việc bạn phụ trách hoặc tạo đang đến hạn trong vòng ${hours} giờ.`,
    '',
    `Tên công việc: ${task.title}`,
    `Hạn hoàn thành: ${deadline}`,
    'Trạng thái: Chưa hoàn thành',
    '',
    'Vui lòng mở TaskManager để theo dõi và hoàn thành công việc.',
    'Đây là email thông báo tự động từ TaskManager.'
  ].join('\n');
}

function safeErrorCode(error) {
  const code = String(error?.code || 'SEND_FAILED')
    .replace(/[^A-Za-z0-9_-]/g, '').slice(0, 40);
  return `SMTP_ERROR_${code || 'SEND_FAILED'}`;
}

function createTransport(config) {
  const nodemailer = require('nodemailer');
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: config.port,
    secure: config.port === 465,
    requireTLS: config.port !== 465,
    auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
    connectionTimeout: 8000,
    greetingTimeout: 8000,
    socketTimeout: 12000,
    tls: { rejectUnauthorized: true }
  });
}

// One initial attempt and at most two retries per recipient + deadline.
// Only a definitive failed response is retried automatically. A pending email
// with attempts > 0 may already have been accepted before a process crash;
// resending it automatically could deliver duplicates.
const MAX_TOTAL_ATTEMPTS = 3;
const RETRY_DELAY_MS = 5 * 60 * 1000;
const UNCERTAIN_AFTER_MS = 15 * 60 * 1000;

function attemptResult(outcome, retried = false) {
  return { outcome, retried };
}

async function markFailed(claimedLog, errorCode) {
  try {
    const result = await EmailLog.updateOne({
      _id: claimedLog._id,
      status: 'pending',
      attempts: claimedLog.attempts
    }, {
      $set: { status: 'failed', errorMessage: errorCode }
    });
    if (result.matchedCount !== 1) {
      console.error('D5_FAILED_STATUS_NOT_CONFIRMED');
      return 'logFailures';
    }
    return 'failed';
  } catch (error) {
    console.error('D5_FAILED_UPDATE_FAILED:', error?.code || 'database_error');
    return 'logFailures';
  }
}

async function sendReminderOnce(task, user, hours, config, getTransport, now = new Date()) {
  // Unique partial index: one log per task, recipient and due date.
  // Retry updates that same log; never creates another one for this key.
  const email = String(user.email || '').trim().toLowerCase();
  if (!email) return attemptResult('skipped');
  const key = {
    taskId: task._id,
    recipientEmail: email,
    eventType: EVENT_TYPE,
    reminderDueDate: new Date(task.dueDate)
  };

  let log;
  let created = false;
  try {
    log = await EmailLog.create({
      ...key,
      subject: SUBJECT,
      status: 'pending', attempts: 0, errorMessage: null
    });
    created = true;
  } catch (error) {
    if (error?.code !== 11000) {
      console.error('D5_LOG_CREATE_FAILED:', error?.code || 'database_error');
      return attemptResult('logFailures');
    }
    try {
      log = await EmailLog.findOne(key);
    } catch (lookupError) {
      console.error('D5_LOG_LOOKUP_FAILED:', lookupError?.code || 'database_error');
      return attemptResult('logFailures');
    }
    if (!log) return attemptResult('duplicate');
  }

  if (log.status === 'sent') return attemptResult('duplicate');
  const attempts = Number(log.attempts || 0);
  if (attempts >= MAX_TOTAL_ATTEMPTS && log.status === 'failed') {
    return attemptResult('exhausted');
  }

  // Avoid creating attempts while SMTP is unavailable or address is synthetic.
  if (!config.ready || isTestEmail(email)) {
    if (created && isTestEmail(email)) {
      await EmailLog.updateOne({ _id: log._id, attempts: 0 }, {
        $set: { errorMessage: 'Địa chỉ thử nghiệm; SMTP không được gửi.' }
      }).catch(error => console.error('D5_PENDING_UPDATE_FAILED:', error?.code || 'database_error'));
    }
    return attemptResult(log.status === 'failed' ? 'deferred' : 'pending');
  }

  let filter;
  let retried = false;
  if (log.status === 'pending' && attempts === 0) {
    // A never-attempted pending log (e.g. previous SMTP config missing).
    filter = { _id: log._id, status: 'pending', attempts: 0 };
  } else if (log.status === 'failed' && attempts < MAX_TOTAL_ATTEMPTS) {
    const lastUpdate = new Date(log.updatedAt || log.createdAt).getTime();
    if (!Number.isFinite(lastUpdate) || lastUpdate > new Date(now).getTime() - RETRY_DELAY_MS) {
      return attemptResult('deferred');
    }
    // Optimistic compare-and-swap: only one worker may claim this failed log.
    filter = {
      _id: log._id, status: 'failed', attempts,
      updatedAt: log.updatedAt
    };
    retried = true;
  } else if (log.status === 'pending' && attempts > 0) {
    const lastUpdate = new Date(log.updatedAt || log.createdAt).getTime();
    if (Number.isFinite(lastUpdate) && lastUpdate <= new Date(now).getTime() - UNCERTAIN_AFTER_MS) {
      // No auto retry: the SMTP outcome may be unknown after a crash.
      console.warn('D5_PENDING_OUTCOME_UNCERTAIN:', String(log._id));
      return attemptResult('uncertain');
    }
    return attemptResult('duplicate');
  } else {
    return attemptResult('duplicate');
  }

  let claimed;
  try {
    claimed = await EmailLog.findOneAndUpdate(filter, {
      $set: { status: 'pending', errorMessage: null, sentAt: null },
      $inc: { attempts: 1 }
    }, { new: true });
  } catch (error) {
    console.error('D5_ATTEMPT_CLAIM_FAILED:', error?.code || 'database_error');
    return attemptResult('logFailures');
  }
  if (!claimed) return attemptResult('duplicate');

  let smtpResult;
  try {
    smtpResult = await getTransport().sendMail({
      from: process.env.SMTP_FROM,
      to: email,
      subject: SUBJECT,
      text: reminderEmailText(task, hours)
    });
  } catch (error) {
    console.error('D5_SMTP_SEND_FAILED:', error?.code || 'send_error');
    return attemptResult(await markFailed(claimed, safeErrorCode(error)), retried);
  }

  const accepted = (smtpResult.accepted || []).some(
    address => String(address).trim().toLowerCase() === email
  );
  if (!accepted) {
    return attemptResult(await markFailed(claimed, 'SMTP_REJECTED_RECIPIENT'), retried);
  }

  // A successful SMTP send must NEVER become 'failed' because a later
  // database update failed: that would incorrectly trigger another send.
  try {
    const saved = await EmailLog.updateOne({
      _id: claimed._id, status: 'pending', attempts: claimed.attempts
    }, {
      $set: { status: 'sent', sentAt: new Date(), errorMessage: null }
    });
    if (saved.matchedCount !== 1) {
      console.error('D5_SENT_STATUS_NOT_CONFIRMED');
      return attemptResult('logFailures', retried);
    }
    return attemptResult('sent', retried);
  } catch (error) {
    console.error('D5_SENT_STATUS_UPDATE_FAILED:', error?.code || 'database_error');
    // Leave pending with attempts > 0 for manual review; do not send again.
    return attemptResult('logFailures', retried);
  }
}

async function runReminderSweep({ mode = 'preview', hours = 24, now = new Date() } = {}) {
  if (!['preview', 'send'].includes(mode)) throw new Error('D5_INVALID_MODE');
  const start = new Date(now);
  const end = new Date(start.getTime() + hours * 60 * 60 * 1000);
  const tasks = await Task.find({
    status: { $ne: 'completed' },
    dueDate: { $gte: start, $lte: end }
  }).sort({ dueDate: 1 }).limit(200).lean();

  const summary = { mode, hours, matchingTasks: tasks.length, recipients: 0,
    sent: 0, pending: 0, failed: 0, duplicate: 0, skipped: 0,
    logFailures: 0, retried: 0, deferred: 0, exhausted: 0, uncertain: 0 };

  let transport;
  const config = smtpConfig();
  const getTransport = () => {
    if (!transport) transport = createTransport(config);
    return transport;
  };

  for (const task of tasks) {
    if (!isDueSoon(task, start, hours)) continue;
    const ids = uniqueRecipientIds(task);
    if (ids.length === 0) continue;
    const users = await User.find({ _id: { $in: ids } })
      .select('email fullName').lean();
    summary.recipients += users.filter(user => !!user.email).length;
    if (mode === 'preview') continue;

    // Serial delivery avoids SMTP bursts and oversized task-related loops.
    for (const user of users) {
      const result = await sendReminderOnce(task, user, hours, config, getTransport, start);
      summary[result.outcome] += 1;
      if (result.retried) summary.retried += 1;
    }
  }
  if (tasks.length === 200) console.warn('D5_REMINDER_BATCH_LIMIT_200');
  return summary;
}

function startDueReminderScheduler(env = process.env) {
  const mode = String(env.D5_REMINDER_MODE || 'off').toLowerCase().trim();
  if (mode === 'off') {
    console.log('D5_REMINDER_OFF (use D5_REMINDER_MODE=preview or send)');
    return null;
  }
  if (!['preview', 'send'].includes(mode)) {
    console.error('D5_INVALID_MODE: set off, preview or send');
    return null;
  }
  const hours = reminderHours(env);
  const intervalMinutes = reminderIntervalMinutes(env);
  let busy = false;

  async function tick() {
    if (busy) return;
    busy = true;
    try {
      if (mode === 'send') {
        // Required before creating email logs to guarantee no duplicates.
        await EmailLog.createIndexes();
      }
      const summary = await runReminderSweep({ mode, hours });
      console.log('D5_REMINDER_SWEEP:', JSON.stringify(summary));
    } catch (error) {
      console.error('D5_SWEEP_FAILED:', error?.code || error?.message || 'unknown');
    } finally {
      busy = false;
    }
  }

  console.log(`D5_REMINDER_START: mode=${mode} hours=${hours} intervalMinutes=${intervalMinutes}`);
  void tick();
  const timer = setInterval(() => { void tick(); }, intervalMinutes * 60 * 1000);
  timer.unref?.();
  return timer;
}

module.exports = {
  reminderHours, reminderIntervalMinutes, isDueSoon, uniqueRecipientIds,
  reminderEmailText, runReminderSweep, startDueReminderScheduler
};
