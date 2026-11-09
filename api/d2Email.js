'use strict';

// D2: Notify the recipient only after a NEW share was successfully saved.
// Reuse D1 SMTP settings; never store SMTP secrets in source or log raw errors.
const { smtpConfig, isTestEmail } = require('./d1Email');
const SUBJECT = 'TaskManager - Bạn được chia sẻ công việc';

function shareEmailText(task, permission) {
  const role = permission === 'editor' ? 'Editor (được chỉnh sửa)' : 'Viewer (chỉ xem)';
  const dueDate = task.dueDate
    ? new Date(task.dueDate).toISOString().slice(0, 10)
    : 'Chưa thiết lập';
  return [
    'Một công việc vừa được chia sẻ với bạn trong TaskManager.',
    '',
    `Tên công việc: ${task.title}`,
    `Quyền được cấp: ${role}`,
    `Hạn hoàn thành: ${dueDate}`,
    '',
    'Vui lòng đăng nhập ứng dụng TaskManager để xem công việc.',
    'Đây là email thông báo tự động từ TaskManager.'
  ].join('\n');
}

function safeErrorCode(error) {
  const code = String(error?.code || 'SEND_FAILED')
    .replace(/[^A-Za-z0-9_-]/g, '').slice(0, 40);
  return `SMTP_ERROR_${code || 'SEND_FAILED'}`;
}

async function notifyNewShare(task, recipient, permission) {
  const summary = {
    newRecipientsCount: 1,
    sent: 0,
    pending: 0,
    failed: 0,
    logFailures: 0
  };

  let log;
  try {
    const EmailLog = require('./models/EmailLog');
    log = await EmailLog.create({
      taskId: task._id,
      recipientEmail: recipient.email,
      eventType: 'task_shared',
      subject: SUBJECT,
      status: 'pending',
      attempts: 0,
      errorMessage: null
    });
  } catch (error) {
    console.error('D2_EMAIL_LOG_CREATE_FAILED:', error?.code || 'database_error');
    summary.logFailures = 1;
    return summary;
  }

  const config = smtpConfig();
  const testAddress = isTestEmail(recipient.email);
  if (!config.ready || testAddress) {
    if (testAddress) {
      try {
        const EmailLog = require('./models/EmailLog');
        await EmailLog.updateOne({ _id: log._id }, {
          $set: { errorMessage: 'Địa chỉ thử nghiệm; SMTP không được gửi.' }
        });
      } catch (error) {
        console.error('D2_PENDING_LOG_UPDATE_FAILED:', error?.code || 'database_error');
        summary.logFailures = 1;
      }
    }
    summary.pending = 1;
    return summary;
  }

  try {
    const EmailLog = require('./models/EmailLog');
    await EmailLog.updateOne({ _id: log._id }, { $inc: { attempts: 1 } });

    const nodemailer = require('nodemailer');
    const transport = nodemailer.createTransport({
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
    const result = await transport.sendMail({
      from: process.env.SMTP_FROM,
      to: recipient.email,
      subject: SUBJECT,
      text: shareEmailText(task, permission)
    });
    const accepted = (result.accepted || []).some(
      address => String(address).toLowerCase() === recipient.email.toLowerCase()
    );
    if (!accepted) {
      await EmailLog.updateOne({ _id: log._id }, {
        $set: { status: 'failed', errorMessage: 'SMTP_REJECTED_RECIPIENT' }
      });
      summary.failed = 1;
      return summary;
    }

    await EmailLog.updateOne({ _id: log._id }, {
      $set: { status: 'sent', sentAt: new Date(), errorMessage: null }
    });
    summary.sent = 1;
    return summary;
  } catch (error) {
    console.error('D2_SMTP_SEND_FAILED:', error?.code || 'send_error');
    try {
      const EmailLog = require('./models/EmailLog');
      await EmailLog.updateOne({ _id: log._id }, {
        $set: { status: 'failed', errorMessage: safeErrorCode(error) }
      });
    } catch (updateError) {
      console.error('D2_FAIL_LOG_UPDATE_FAILED:', updateError?.code || 'database_error');
      summary.logFailures = 1;
    }
    summary.failed = 1;
    return summary;
  }
}

module.exports = { shareEmailText, notifyNewShare };
