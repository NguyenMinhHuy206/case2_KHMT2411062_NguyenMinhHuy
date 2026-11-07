'use strict';
const mongoose = require('mongoose');
const { Schema } = mongoose;

const schema = new Schema({
  taskId: { type: Schema.Types.ObjectId, ref: 'Task', required: true },
  userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
  action: { type: String, required: true },
  details: { type: Schema.Types.Mixed, default: () => ({}) }
}, {
  timestamps: true,
  collection: 'task_activities'
});

module.exports = mongoose.model('TaskActivity', schema);