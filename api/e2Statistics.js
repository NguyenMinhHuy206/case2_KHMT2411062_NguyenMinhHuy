'use strict';

// E2: Assignment statistics of the authenticated user only.
// Each count is a count of distinct Task documents, so repeated links do not inflate it.
const express = require('express');
const Task = require('./models/Task');

function createE2StatisticsRouter(auth) {
  const router = express.Router();

  // GET /api/statistics/assignments
  router.get('/assignments', auth, async (req, res) => {
    try {
      // auth middleware populates _id from a verified token, not from request input.
      const userId = req.user?._id;
      if (!userId) {
        return res.status(401).json({ message: 'Ban chua dang nhap.' });
      }

      // Counts are independent: a primary assignee can also be an assignee.
      const [assignedToMe, primaryResponsible] = await Promise.all([
        Task.countDocuments({ assigneeIds: userId }),
        Task.countDocuments({ primaryAssigneeId: userId })
      ]);

      return res.json({ assignedToMe, primaryResponsible });
    } catch (error) {
      console.error('E2_ASSIGNMENT_STATISTICS_ERROR:', error);
      return res.status(500).json({ message: 'Khong the tai thong ke phan cong.' });
    }
  });

  return router;
}

module.exports = createE2StatisticsRouter;
