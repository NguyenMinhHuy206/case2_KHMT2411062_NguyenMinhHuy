'use strict';

// E3: Deadline statistics for tasks visible to the authenticated user.
// MongoDB stores task deadlines as UTC-midnight calendar dates (YYYY-MM-DD).
// Compare date-only values, not timestamps, so a task due today is NOT overdue.
const express = require('express');
const Task = require('./models/Task');
const TaskShare = require('./models/TaskShare');

const TIME_ZONE = 'Asia/Ho_Chi_Minh';
const SOON_DAYS = 7; // today through the next seven calendar days (inclusive)

function todayInTimeZone(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit'
  }).formatToParts(now);
  const pick = name => parts.find(part => part.type === name)?.value;
  return `${pick('year')}-${pick('month')}-${pick('day')}`;
}

function dayNumber(isoDate) {
  if (typeof isoDate !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(isoDate)) return NaN;
  const day = new Date(`${isoDate}T00:00:00.000Z`);
  if (!Number.isFinite(day.getTime()) || day.toISOString().slice(0, 10) !== isoDate) return NaN;
  return Math.floor(day.getTime() / 86400000);
}

function dateOnly(input) {
  if (input == null || input === '') return null;
  const date = input instanceof Date ? input : new Date(input);
  if (!Number.isFinite(date.getTime())) return null;
  return date.toISOString().slice(0, 10);
}

function summarizeDeadlines(tasks, today = todayInTimeZone(), windowDays = SOON_DAYS) {
  const todayNumber = dayNumber(today);
  if (!Number.isFinite(todayNumber) || !Number.isInteger(windowDays) || windowDays < 1 || windowDays > 30) {
    throw new Error('INVALID_DEADLINE_STATISTICS_PARAMETERS');
  }
  const soon = [];
  const overdue = [];
  for (const task of tasks) {
    if (task.status === 'completed') continue;
    const dueDate = dateOnly(task.dueDate);
    if (!dueDate) continue;
    const daysRemaining = dayNumber(dueDate) - todayNumber;
    if (!Number.isFinite(daysRemaining) || daysRemaining > windowDays) continue;
    const id = task.legacyId || (task._id == null ? null : String(task._id));
    if (!id) continue;
    const item = {
      id: String(id),
      title: String(task.title || 'Công việc chưa có tên'),
      dueDate,
      status: task.status === 'todo' ? 'pending' : task.status,
      priority: task.priority || 'medium',
      daysRemaining
    };
    if (daysRemaining < 0) overdue.push(item);
    else soon.push(item);
  }
  // Nearest upcoming first; earliest overdue first.
  soon.sort((a, b) => a.daysRemaining - b.daysRemaining || a.id.localeCompare(b.id));
  overdue.sort((a, b) => a.daysRemaining - b.daysRemaining || a.id.localeCompare(b.id));
  return {
    today, timeZone: TIME_ZONE, windowDays,
    soonCount: soon.length, overdueCount: overdue.length,
    soon, overdue
  };
}

function createE3StatisticsRouter(auth) {
  const router = express.Router();
  router.get('/deadlines', auth, async (req, res) => {
    try {
      const userId = req.user?._id;
      if (!userId) return res.status(401).json({ message: 'Ban chua dang nhap.' });
      const sharedTaskIds = await TaskShare.find({ userId }).distinct('taskId');
      const tasks = await Task.find({
        dueDate: { $ne: null },
        status: { $ne: 'completed' },
        $or: [
          { createdBy: userId },
          { assigneeIds: userId },
          { _id: { $in: sharedTaskIds } }
        ]
      }).select('_id legacyId title dueDate status priority').lean();
      return res.json(summarizeDeadlines(tasks));
    } catch (error) {
      console.error('E3_DEADLINE_STATISTICS_ERROR:', error);
      return res.status(500).json({ message: 'Khong the tai thong ke thoi han.' });
    }
  });
  return router;
}

module.exports = createE3StatisticsRouter;
module.exports.summarizeDeadlines = summarizeDeadlines;
module.exports.todayInTimeZone = todayInTimeZone;
