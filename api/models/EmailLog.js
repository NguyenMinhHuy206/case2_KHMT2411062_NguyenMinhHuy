'use strict';
const mongoose = require('mongoose');
const { Schema } = mongoose;

const schema = new Schema({
  taskId: { type: Schema.Types.ObjectId, ref: 'Task', default: null },
  recipientEmail: { type: String, required: true },
  eventType: { type: String, required: true },
  subject: { type: String, required: true },
  status: {
    type: String,
    enum: ['pending', 'sent', 'failed'],
    default: 'pending'
  },
  attempts: { type: Number, default: 0 },
  errorMessage: { type: String, default: null },
  sentAt: { type: Date, default: null },
  reminderDueDate: { type: Date, default: null }
}, {
  timestamps: true,
  collection: 'email_logs'
});

// One reminder for each task, recipient and deadline (including server restarts).
// Other D1-D4 logs are not restricted by this partial index.
schema.index(
  { taskId: 1, recipientEmail: 1, eventType: 1, reminderDueDate: 1 },
  { unique: true, name: 'd5_unique_reminder_per_deadline',
    partialFilterExpression: { eventType: 'task_due_reminder' } }
);
module.exports = mongoose.model('EmailLog', schema);