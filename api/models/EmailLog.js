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
  sentAt: { type: Date, default: null }
}, {
  timestamps: true,
  collection: 'email_logs'
});

module.exports = mongoose.model('EmailLog', schema);