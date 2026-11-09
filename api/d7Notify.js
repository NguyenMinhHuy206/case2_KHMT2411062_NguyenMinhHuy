'use strict';

// D7: store independent in-app notifications after successful task actions.
// Notification failures never undo an already-saved task/assignment/share.
const Notification = require('./models/Notification');
const TaskShare = require('./models/TaskShare');
const { detectImportantChanges } = require('./d3Email');
const { isNewCompletion } = require('./d4Email');

async function store(task, recipients, type, title, message) {
  const ids = [...new Set((recipients || []).filter(Boolean).map(id => String(id)))];
  if (!ids.length) return;
  try {
    await Notification.insertMany(ids.map(userId => ({
      userId, taskId: task._id, type, title,
      message: String(message).slice(0, 500), isRead: false
    })), { ordered: false });
  } catch (error) {
    console.error('D7_NOTIFICATION_CREATE_FAILED:', error?.code || 'database_error');
  }
}

async function relatedIds(task, actorId) {
  const shares = await TaskShare.find({ taskId: task._id }).select('userId').lean();
  return [...new Set([
    task.createdBy,
    ...(task.assigneeIds || []),
    ...shares.map(share => share.userId)
  ].filter(Boolean).map(String))].filter(id => id !== String(actorId));
}

async function notifyAssignment(task, newUsers) {
  await store(task, newUsers.map(user => user._id), 'task_assigned',
    'Bạn được giao công việc', `Bạn vừa được giao: ${task.title}`);
}

async function notifyShare(task, recipient, permission) {
  await store(task, [recipient._id], 'task_shared',
    'Công việc được chia sẻ',
    `Bạn được chia sẻ công việc "${task.title}" với quyền ${permission === 'editor' ? 'chỉnh sửa' : 'xem'}.`);
}

async function notifyImportantChange(task, before, actorId) {
  const changes = detectImportantChanges(before, task);
  if (!changes.length) return;
  try {
    const fields = changes.map(change => ({
      priority: 'độ ưu tiên', dueDate: 'hạn hoàn thành',
      startDate: 'ngày bắt đầu', title: 'tên công việc'
    })[change.field] || change.field).join(', ');
    await store(task, await relatedIds(task, actorId), 'task_updated',
      'Công việc được cập nhật', `Công việc "${task.title}" đã thay đổi: ${fields}.`);
  } catch (error) {
    console.error('D7_NOTIFICATION_RECIPIENT_FAILED:', error?.code || 'database_error');
  }
}

async function notifyCompletion(task, beforeStatus, actorId) {
  if (!isNewCompletion(beforeStatus, task.status)) return;
  try {
    await store(task, await relatedIds(task, actorId), 'task_completed',
      'Công việc hoàn thành', `Công việc "${task.title}" đã hoàn thành.`);
  } catch (error) {
    console.error('D7_NOTIFICATION_RECIPIENT_FAILED:', error?.code || 'database_error');
  }
}

async function notifyStatus(task, beforeStatus, actorId) {
  if (String(beforeStatus) === String(task.status) || task.status === 'completed') return;
  try {
    const status = task.status === 'in_progress' ? 'Đang thực hiện' : 'Chưa thực hiện';
    await store(task, await relatedIds(task, actorId), 'task_status_changed',
      'Trạng thái công việc thay đổi', `Công việc "${task.title}" chuyển sang: ${status}.`);
  } catch (error) {
    console.error('D7_NOTIFICATION_RECIPIENT_FAILED:', error?.code || 'database_error');
  }
}

module.exports = {
  notifyAssignment, notifyShare, notifyImportantChange, notifyCompletion, notifyStatus
};
