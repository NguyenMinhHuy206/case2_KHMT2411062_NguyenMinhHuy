'use strict';

const mongoose = require('mongoose');
const Schema = mongoose.Schema;

const taskSchema = new Schema({
  title: {
    type: String,
    required: true,
    trim: true,
    maxlength: 200
  },

  description: {
    type: String,
    default: '',
    maxlength: 5000
  },

  createdBy: {
    type: Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },

  assigneeIds: {
    type: [{
      type: Schema.Types.ObjectId,
      ref: 'User'
    }],
    default: []
  },

  primaryAssigneeId: {
    type: Schema.Types.ObjectId,
    ref: 'User',
    default: null
  },

  startDate: {
    type: Date,
    default: null
  },

  dueDate: {
    type: Date,
    default: null
  },

  priority: {
    type: String,
    enum: ['low', 'medium', 'high'],
    default: 'medium'
  },

  status: {
    type: String,
    enum: ['pending', 'todo', 'in_progress', 'completed'],
    default: 'pending'
  },

  legacyId: {
    type: String,
    unique: true,
    sparse: true
  }
}, {
  timestamps: true,
  collection: 'tasks'
});

taskSchema.index({ createdBy: 1, createdAt: -1 });
taskSchema.index({ assigneeIds: 1 });

module.exports = mongoose.model('Task', taskSchema);