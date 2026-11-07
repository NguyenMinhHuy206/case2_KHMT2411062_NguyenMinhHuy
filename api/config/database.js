'use strict';

const mongoose = require('mongoose');
const path = require('path');
const dotenv = require('dotenv');

dotenv.config({
  path: path.join(__dirname, '..', '.env')
});

async function connectDatabase() {
  const uri = process.env.MONGODB_URI;
  const dbName = process.env.MONGODB_DB || 'taskmanager';

  if (!uri) {
    throw new Error('Chua cau hinh MONGODB_URI trong api/.env');
  }

  await mongoose.connect(uri, {
    dbName,
    serverSelectionTimeoutMS: 15000
  });

  console.log('MongoDB connected:', mongoose.connection.name);

  return mongoose.connection;
}

module.exports = {
  connectDatabase,
  mongoose
};