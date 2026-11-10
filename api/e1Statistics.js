'use strict';

// E1: Count each task accessible to the signed-in user exactly once.
// A task can simultaneously be created, assigned and shared with the same user.
const express = require('express');
const Task = require('./models/Task');
const TaskShare = require('./models/TaskShare');

function summarizeTasks(tasks) {
  const byStatus = { pending: 0, in_progress: 0, completed: 0, other: 0 };
  for (const task of tasks) {
    const status = task.status === 'todo' ? 'pending' : task.status;
    if (Object.prototype.hasOwnProperty.call(byStatus, status) && status !== 'other') {
      byStatus[status] += 1;
    } else {
      byStatus.other += 1;
    }
  }
  return { total: tasks.length, byStatus };
}

function createE1StatisticsRouter(auth) {
  const router = express.Router();

  // GET /api/statistics/tasks -- counts from MongoDB, never from client input.
  router.get('/tasks', auth, async (req, res) => {
    try {
      const userId = req.user._id; // Mongo ObjectId obtained from verified JWT.
      const sharedTaskIds = await TaskShare.find({ userId }).distinct('taskId');
      const tasks = await Task.find({
        $or: [
          { createdBy: userId },
          { assigneeIds: userId },
          { _id: { $in: sharedTaskIds } }
        ]
      }).select('_id status').lean();

      return res.json(summarizeTasks(tasks));
    } catch (error) {
      console.error('E1_STATISTICS_ERROR:', error);
      return res.status(500).json({ message: 'Khong the tai thong ke cong viec.' });
    }
  });
  return router;
}

module.exports = createE1StatisticsRouter;
module.exports.summarizeTasks = summarizeTasks;
