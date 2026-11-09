'use strict';

// D1 – Only new assignees receive emails. No SMTP credentials are hard-coded.
// EMAIL_MODE=off is safe for development: log as pending, never claim "sent".
const SUBJECT = 'TaskManager - Bạn được giao công việc mới';

function newAssignmentRecipients(previousIds, selectedUsers) {
  const previous = new Set((previousIds || []).map(id => String(id)));
  return (selectedUsers || []).filter(user => !previous.has(String(user._id)));
}

function isTestEmail(address) {
  const domain = String(address || '').toLowerCase().split('@')[1] || '';
  return ['example.com', 'example.net', 'example.org', 'invalid'].some(
    test => domain === test || domain.endsWith('.' + test)
  ) || domain.endsWith('.invalid');
}

function smtpConfig(env = process.env) {
  const enabled = String(env.EMAIL_MODE || 'off').toLowerCase() === 'smtp';
  const port = Number(env.SMTP_PORT || 587);
  const ready = enabled && !!env.SMTP_HOST && !!env.SMTP_USER &&
    !!env.SMTP_PASS && !!env.SMTP_FROM && Number.isInteger(port) &&
    port >= 1 && port <= 65535;
  return { enabled, ready, port };
}

function assignmentEmailText(task) {
  const due = task.dueDate ? new Date(task.dueDate).toISOString().slice(0, 10) : 'Chưa thiết lập';
  return [
    'Bạn vừa được giao một công việc trong TaskManager.',
    '',
    `Tên công việc: ${task.title}`,
    `Hạn hoàn thành: ${due}`,
    '',
    'Vui lòng đăng nhập ứng dụng TaskManager để xem thông tin và tiến độ.',
    'Đây là email thông báo tự động từ TaskManager.'
  ].join('\n');
}

function safeSendError(err) {
  // Do not persist raw SMTP error strings: they can contain email addresses or secrets.
  const code = String(err && err.code || 'SEND_FAILED').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 40);
  return `SMTP_ERROR_${code}`;
}

let transporter;
function transportFor(config) {
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
  return transporter;
}

async function processRecipient(task, recipient, config) {
  const EmailLog = require('./models/EmailLog');
  const testAddress = isTestEmail(recipient.email);
  let log;
  try {
    log = await EmailLog.create({
      taskId: task._id,
      recipientEmail: recipient.email,
      eventType: 'task_assigned',
      subject: SUBJECT,
      status: 'pending',
      attempts: 0,
      errorMessage: null
    });
  } catch (err) {
    console.error('D1_EMAIL_LOG_CREATE_FAILED:', err?.code || 'database_error');
    return 'logFailures';
  }

  if (!config.ready || testAddress) {
    // Mail is waiting for a valid SMTP configuration/recipient; never mark sent.
    if (testAddress) {
      await EmailLog.updateOne({ _id: log._id }, {
        $set: { errorMessage: 'Địa chỉ thử nghiệm; SMTP không được gửi.' }
      }).catch(err => console.error('D1_PENDING_LOG_UPDATE_FAILED:', err?.code || 'database_error'));
    }
    return 'pending';
  }

  try {
    await EmailLog.updateOne({ _id: log._id }, {
      $inc: { attempts: 1 }
    });
    const result = await transportFor(config).sendMail({
      from: process.env.SMTP_FROM,
      to: recipient.email,
      subject: SUBJECT,
      text: assignmentEmailText(task)
    });
    const accepted = (result.accepted || []).some(
      address => String(address).toLowerCase() === recipient.email.toLowerCase()
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
  } catch (err) {
    console.error('D1_SMTP_SEND_FAILED:', err?.code || 'send_error');
    await EmailLog.updateOne({ _id: log._id }, {
      $set: { status: 'failed', errorMessage: safeSendError(err) }
    }).catch(updateErr => console.error('D1_FAIL_LOG_UPDATE_FAILED:', updateErr?.code || 'database_error'));
    return 'failed';
  }
}

async function notifyNewAssignees(task, recipients) {
  const config = smtpConfig();
  const summary = { newRecipientsCount: recipients.length, sent: 0, pending: 0, failed: 0, logFailures: 0 };
  // Limit concurrency: the assignment endpoint permits up to 30 recipients.
  let index = 0;
  async function worker() {
    while (index < recipients.length) {
      const recipient = recipients[index++];
      try {
        const outcome = await processRecipient(task, recipient, config);
        summary[outcome] += 1;
      } catch (err) {
        // Never return a success status for a failed notification.
        console.error('D1_EMAIL_WORKER_ERROR:', err?.code || 'unexpected_error');
        summary.logFailures += 1;
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(3, recipients.length) }, () => worker()));
  return summary;
}

module.exports = {
  newAssignmentRecipients, isTestEmail, smtpConfig,
  assignmentEmailText, notifyNewAssignees
};
