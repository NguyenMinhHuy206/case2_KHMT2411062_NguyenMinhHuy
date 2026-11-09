'use strict';

// D4 - Notify related users when a task transitions to completed.
// Email failures must never roll back a successfully saved status change.
const SUBJECT = 'TaskManager - Công việc đã hoàn thành';

function isNewCompletion(beforeStatus, afterStatus) {
  return String(beforeStatus) !== 'completed' && String(afterStatus) === 'completed';
}

function completionEmailText(task) {
  const due = task.dueDate ? new Date(task.dueDate).toISOString().slice(0, 10) : 'Chưa thiết lập';
  return [
    'Một công việc liên quan đến bạn đã được đánh dấu hoàn thành trong TaskManager.',
    '',
    `Tên công việc: ${task.title}`,
    `Hạn hoàn thành: ${due}`,
    'Trạng thái mới: Đã hoàn thành',
    '',
    'Vui lòng mở ứng dụng TaskManager để xem công việc.',
    'Đây là email thông báo tự động từ TaskManager.'
  ].join('\n');
}

function safeErrorCode(error) {
  const code = String(error?.code || 'SEND_FAILED')
    .replace(/[^A-Za-z0-9_-]/g, '').slice(0, 40);
  return `SMTP_ERROR_${code || 'SEND_FAILED'}`;
}

async function notifyTaskCompleted(task, previousStatus, actorId) {
  const summary = { completedNow: isNewCompletion(previousStatus, task.status), recipientCount: 0,
    sent: 0, pending: 0, failed: 0, logFailures: 0 };
  if (!summary.completedNow) return summary;

  let recipients;
  try {
    const User = require('./models/User');
    const TaskShare = require('./models/TaskShare');
    const shares = await TaskShare.find({ taskId: task._id }).select('userId').lean();
    const ids = [task.createdBy, ...(task.assigneeIds || []), ...shares.map(share => share.userId)];
    const uniqueIds = [...new Set(ids.filter(Boolean).map(String))]
      .filter(id => id !== String(actorId));
    recipients = uniqueIds.length
      ? await User.find({ _id: { $in: uniqueIds } }).select('email fullName').lean()
      : [];
    recipients = recipients.filter(user => user.email);
    summary.recipientCount = recipients.length;
  } catch (error) {
    console.error('D4_RECIPIENT_LOOKUP_FAILED:', error?.code || 'database_error');
    summary.logFailures++;
    return summary;
  }

  const { smtpConfig, isTestEmail } = require('./d1Email');
  const config = smtpConfig();
  const body = completionEmailText(task);
  let transporter;
  let next = 0;

  async function sendTo(user) {
    const EmailLog = require('./models/EmailLog');
    let log;
    try {
      log = await EmailLog.create({
        taskId: task._id,
        recipientEmail: user.email,
        eventType: 'task_completed',
        subject: SUBJECT,
        status: 'pending',
        attempts: 0,
        errorMessage: null
      });
    } catch (error) {
      console.error('D4_LOG_CREATE_FAILED:', error?.code || 'database_error');
      return 'logFailures';
    }

    if (!config.ready || isTestEmail(user.email)) {
      if (isTestEmail(user.email)) {
        await EmailLog.updateOne({ _id: log._id }, {
          $set: { errorMessage: 'Địa chỉ thử nghiệm; SMTP không được gửi.' }
        }).catch(error => console.error('D4_PENDING_UPDATE_FAILED:', error?.code || 'database_error'));
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
      console.error('D4_SMTP_SEND_FAILED:', error?.code || 'send_error');
      await EmailLog.updateOne({ _id: log._id }, {
        $set: { status: 'failed', errorMessage: safeErrorCode(error) }
      }).catch(updateError => console.error('D4_FAILED_UPDATE_FAILED:', updateError?.code || 'database_error'));
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
        console.error('D4_EMAIL_WORKER_FAILED:', error?.code || 'unexpected_error');
        summary.logFailures++;
      }
    }
  }

  await Promise.all(Array.from({ length: Math.min(3, recipients.length) }, worker));
  return summary;
}

module.exports = { isNewCompletion, completionEmailText, notifyTaskCompleted };