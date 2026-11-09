'use strict';

// D7: user-scoped notifications and task access checks.
const express = require('express');
const mongoose = require('mongoose');
const Task = require('./models/Task');
const TaskShare = require('./models/TaskShare');
const Notification = require('./models/Notification');

async function canOpenTask(taskId, userId) {
  const task = await Task.findById(taskId).select('createdBy assigneeIds').lean();
  if (!task) return false;
  const id = String(userId);
  if (String(task.createdBy) === id) return true;
  if ((task.assigneeIds || []).some(value => String(value) === id)) return true;
  return Boolean(await TaskShare.exists({ taskId, userId }));
}

module.exports = function createD7Router(auth) {
  const router = express.Router();

  router.get('/', auth, async (req, res) => {
    try {
      const records = await Notification.find({ userId: req.user._id })
        .sort({ createdAt: -1, _id: -1 }).limit(200).lean();
      const taskIds = [...new Set(records.map(record => String(record.taskId)))];
      const tasks = taskIds.length ? await Task.find({ _id: { $in: taskIds } })
        .select('_id legacyId createdBy assigneeIds').lean() : [];
      const shares = taskIds.length ? await TaskShare.find({
        taskId: { $in: taskIds }, userId: req.user._id
      }).select('taskId').lean() : [];
      const shared = new Set(shares.map(row => String(row.taskId)));
      const available = new Map(tasks.filter(task =>
        String(task.createdBy) === String(req.user._id) ||
        (task.assigneeIds || []).some(id => String(id) === String(req.user._id)) ||
        shared.has(String(task._id))
      ).map(task => [String(task._id), task]));
      const visible = records.filter(record => available.has(String(record.taskId)));
      const entries = visible.map(record => {
        const task = available.get(String(record.taskId));
        return {
          id: String(record._id),
          taskId: task.legacyId || String(task._id),
          type: record.type,
          title: record.title,
          message: record.message,
          isRead: record.isRead === true,
          createdAt: record.createdAt
        };
      });
      return res.json({
        notifications: entries,
        total: entries.length,
        unreadCount: entries.filter(item => !item.isRead).length
      });
    } catch (error) {
      console.error('D7_NOTIFICATION_LIST_ERROR:', error?.code || 'database_error');
      return res.status(500).json({ message: 'Không tải được thông báo.' });
    }
  });

  // Matches the visible, access-controlled notifications shown by GET /.
  router.get('/unread-count', auth, async (req, res) => {
    try {
      const records = await Notification.find({ userId: req.user._id, isRead: { $ne: true } })
        .select('taskId isRead').lean();
      const taskIds = [...new Set(records.map(record => String(record.taskId)))];
      const tasks = taskIds.length ? await Task.find({ _id: { $in: taskIds } })
        .select('_id createdBy assigneeIds').lean() : [];
      const shares = taskIds.length ? await TaskShare.find({
        taskId: { $in: taskIds }, userId: req.user._id
      }).select('taskId').lean() : [];
      const shared = new Set(shares.map(row => String(row.taskId)));
      const uid = String(req.user._id);
      const visible = new Set(tasks.filter(task =>
        String(task.createdBy) === uid ||
        (task.assigneeIds || []).some(id => String(id) === uid) ||
        shared.has(String(task._id))
      ).map(task => String(task._id)));
      return res.json({
        unreadCount: records.filter(row => !row.isRead && visible.has(String(row.taskId))).length
      });
    } catch (error) {
      console.error('D7_UNREAD_COUNT_ERROR:', error?.code || 'database_error');
      return res.status(500).json({ message: 'Khong dem duoc thong bao chua doc.' });
    }
  });

  // Mark ONLY the caller's still-accessible notifications as read.
  router.patch('/read-all', auth, async (req, res) => {
    try {
      const unread = await Notification.find({ userId: req.user._id, isRead: false })
        .select('_id taskId').lean();
      if (!unread.length) return res.json({ updatedCount: 0 });
      const taskIds = [...new Set(unread.map(row => String(row.taskId)))];
      const tasks = await Task.find({ _id: { $in: taskIds } })
        .select('_id createdBy assigneeIds').lean();
      const shares = await TaskShare.find({
        taskId: { $in: taskIds }, userId: req.user._id
      }).select('taskId').lean();
      const shared = new Set(shares.map(row => String(row.taskId)));
      const uid = String(req.user._id);
      const visible = new Set(tasks.filter(task =>
        String(task.createdBy) === uid ||
        (task.assigneeIds || []).some(id => String(id) === uid) ||
        shared.has(String(task._id))
      ).map(task => String(task._id)));
      const ids = unread.filter(row => visible.has(String(row.taskId))).map(row => row._id);
      if (!ids.length) return res.json({ updatedCount: 0 });
      const result = await Notification.updateMany(
        { _id: { $in: ids }, userId: req.user._id, isRead: false },
        { $set: { isRead: true } }
      );
      return res.json({ updatedCount: result.modifiedCount || 0 });
    } catch (error) {
      console.error('D7_READ_ALL_ERROR:', error?.code || 'database_error');
      return res.status(500).json({ message: 'Khong danh dau tat ca da doc duoc.' });
    }
  });
  router.patch('/:id/read', auth, async (req, res) => {
    try {
      if (!mongoose.isValidObjectId(req.params.id)) {
        return res.status(404).json({ message: 'Không tìm thấy thông báo.' });
      }
      if (typeof req.body?.isRead !== 'boolean') {
        return res.status(400).json({ message: 'isRead phải là true hoặc false.' });
      }
      const notification = await Notification.findOne({
        _id: req.params.id, userId: req.user._id
      });
      if (!notification || !(await canOpenTask(notification.taskId, req.user._id))) {
        return res.status(404).json({ message: 'Không tìm thấy thông báo hoặc không có quyền.' });
      }
      notification.isRead = req.body.isRead;
      await notification.save();
      return res.json({ id: String(notification._id), isRead: notification.isRead });
    } catch (error) {
      console.error('D7_NOTIFICATION_UPDATE_ERROR:', error?.code || 'database_error');
      return res.status(500).json({ message: 'Không thể thay đổi trạng thái thông báo.' });
    }
  });

  return router;
};
