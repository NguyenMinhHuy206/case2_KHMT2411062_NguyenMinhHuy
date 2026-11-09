'use strict';

// D3 - Notify task participants when key details change. Email failures must
// not undo a task update. Actual delivery state is kept in EmailLog.
const SUBJECT = 'TaskManager - Thông tin công việc đã thay đổi';
const FIELD_LABELS = {
  title: 'Tên công việc',
  priority: 'Mức độ ưu tiên',
  dueDate: 'Hạn hoàn thành'
};
const PRIORITY_LABELS = { low: 'Thấp', medium: 'Trung bình', high: 'Cao' };

function day(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString().slice(0, 10) : null;
}

function snapshotImportantFields(task) {
  return {
    title: String(task.title ?? '').trim(),
    priority: String(task.priority ?? ''),
    dueDate: day(task.dueDate)
  };
}

function formatValue(field, value) {
  if (value == null || value === '') return 'Chưa thiết lập';
  if (field === 'priority') return PRIORITY_LABELS[value] || String(value);
  return String(value);
}

function detectImportantChanges(before, after) {
  const oldState = snapshotImportantFields(before);
  const newState = snapshotImportantFields(after);
  return Object.keys(FIELD_LABELS).filter(field => oldState[field] !== newState[field])
    .map(field => ({
      field,
      label: FIELD_LABELS[field],
      before: formatValue(field, oldState[field]),
      after: formatValue(field, newState[field])
    }));
}

function taskChangeEmailText(task, changes) {
  return [
    'Thông tin quan trọng của một công việc trong TaskManager đã thay đổi.',
    '',
    `Công việc hiện tại: ${task.title}`,
    ...changes.map(change => `${change.label}: ${change.before} -> ${change.after}`),
    '',
    'Vui lòng mở ứng dụng TaskManager để xem thông tin mới nhất.',
    'Đây là email thông báo tự động từ TaskManager.'
  ].join('\n');
}

function safeErrorCode(error) {
  const code = String(error?.code || 'SEND_FAILED')
    .replace(/[^A-Za-z0-9_-]/g, '').slice(0, 40);
  return `SMTP_ERROR_${code || 'SEND_FAILED'}`;
}

async function notifyImportantTaskChanges(task, previousState, actorId) {
  const changes = detectImportantChanges(previousState, task);
  const summary = {
    changedFields: changes.map(change => change.field),
    recipientCount: 0, sent: 0, pending: 0, failed: 0, logFailures: 0
  };
  if (changes.length === 0) return summary;

  let recipients;
  try {
    const User = require('./models/User');
    const TaskShare = require('./models/TaskShare');
    const shares = await TaskShare.find({ taskId: task._id }).select('userId').lean();
    const allIds = [task.createdBy, ...(task.assigneeIds || []), ...shares.map(s => s.userId)];
    const distinctIds = [...new Set(allIds.filter(Boolean).map(String))]
      .filter(id => id !== String(actorId));
    recipients = distinctIds.length
      ? await User.find({ _id: { $in: distinctIds } }).select('email fullName').lean()
      : [];
    recipients = recipients.filter(user => user.email);
    summary.recipientCount = recipients.length;
  } catch (error) {
    console.error('D3_RECIPIENT_LOOKUP_FAILED:', error?.code || 'database_error');
    summary.logFailures++;
    return summary;
  }

  const { smtpConfig, isTestEmail } = require('./d1Email');
  const config = smtpConfig();
  const body = taskChangeEmailText(task, changes);
  let transporter;
  let next = 0;

  async function sendTo(user) {
    const EmailLog = require('./models/EmailLog');
    let log;
    try {
      log = await EmailLog.create({
        taskId: task._id,
        recipientEmail: user.email,
        eventType: 'task_updated',
        subject: SUBJECT,
        status: 'pending',
        attempts: 0,
        errorMessage: null
      });
    } catch (error) {
      console.error('D3_LOG_CREATE_FAILED:', error?.code || 'database_error');
      return 'logFailures';
    }
    if (!config.ready || isTestEmail(user.email)) {
      if (isTestEmail(user.email)) {
        await EmailLog.updateOne({ _id: log._id }, {
          $set: { errorMessage: 'Địa chỉ thử nghiệm; SMTP không được gửi.' }
        }).catch(error => console.error('D3_PENDING_UPDATE_FAILED:', error?.code || 'database_error'));
      }
      return 'pending';
    }

    try {
      await EmailLog.updateOne({ _id: log._id }, { $inc: { attempts: 1 } });
      if (!transporter) {
        const nodemailer = require('nodemailer');
        transporter = nodemailer.createTransport({
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
      const result = await transporter.sendMail({
        from: process.env.SMTP_FROM,
        to: user.email,
        subject: SUBJECT,
        text: body
      });
      const accepted = (result.accepted || []).some(
        address => String(address).toLowerCase() === String(user.email).toLowerCase()
      );
      if (!accepted) {
        await EmailLog.updateOne({ _id: log._id }, {
          $set: { status: 'failed', errorMessage: 'SMTP_REJECTED_RECIPIENT' }
        });
        return 'failed';
      }
      await EmailLog.updateOne({ _id: log._id }, {
        $set: { status: 'sent', sentAt: new Date(), errorMessage: null }
      });
      return 'sent';
    } catch (error) {
      console.error('D3_SMTP_SEND_FAILED:', error?.code || 'send_error');
      await EmailLog.updateOne({ _id: log._id }, {
        $set: { status: 'failed', errorMessage: safeErrorCode(error) }
      }).catch(updateError => console.error('D3_FAILED_UPDATE_FAILED:', updateError?.code || 'database_error'));
      return 'failed';
    }
  }

  async function worker() {
    while (next < recipients.length) {
      const user = recipients[next++];
      try {
        const result = await sendTo(user);
        summary[result] += 1;
      } catch (error) {
        console.error('D3_EMAIL_WORKER_FAILED:', error?.code || 'unexpected_error');
        summary.logFailures += 1;
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(3, recipients.length) }, worker));
  return summary;
}

module.exports = {
  snapshotImportantFields, detectImportantChanges,
  taskChangeEmailText, notifyImportantTaskChanges
};