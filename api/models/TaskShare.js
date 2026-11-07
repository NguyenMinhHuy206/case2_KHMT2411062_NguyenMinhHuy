'use strict';
const mongoose = require('mongoose');
const { Schema } = mongoose;

const schema = new Schema({
  taskId: { type: Schema.Types.ObjectId, ref: 'Task', required: true },
  userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
  permission: {
    type: String,
    enum: ['viewer', 'editor'],
    required: true
  },
  sharedBy: { type: Schema.Types.ObjectId, ref: 'User', required: true }
}, {
  timestamps: true,
  collection: 'task_shares'
});

schema.index({ taskId: 1, userId: 1 }, { unique: true });
module.exports = mongoose.model('TaskShare', schema);