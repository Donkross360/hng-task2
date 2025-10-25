const express = require('express');
const app = express();

// Get environment variables
const APP_POOL = process.env.APP_POOL || 'unknown';
const RELEASE_ID = process.env.RELEASE_ID || 'unknown';

// Chaos simulation state
let chaosMode = false;
let chaosType = 'error'; // 'error' or 'timeout'

// Middleware to add required headers
app.use((req, res, next) => {
  res.setHeader('X-App-Pool', APP_POOL);
  res.setHeader('X-Release-Id', RELEASE_ID);
  next();
});

// Root endpoint - deployment status
app.get('/', (req, res) => {
  const status = {
    service: 'Blue/Green Deployment',
    pool: APP_POOL,
    releaseId: RELEASE_ID,
    status: chaosMode ? 'chaos' : 'healthy',
    chaosMode: chaosMode,
    chaosType: chaosMode ? chaosType : null,
    timestamp: new Date().toISOString(),
    endpoints: {
      version: '/version',
      health: '/healthz',
      chaos: '/chaos/start and /chaos/stop'
    }
  };
  
  res.json(status);
});

// Health check endpoint
app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'healthy', pool: APP_POOL });
});

// Version endpoint
app.get('/version', (req, res) => {
  if (chaosMode && chaosType === 'error') {
    return res.status(500).json({ error: 'Chaos mode: server error' });
  }
  
  if (chaosMode && chaosType === 'timeout') {
    // Simulate timeout by not responding
    return;
  }
  
  res.json({
    version: '1.0.0',
    pool: APP_POOL,
    releaseId: RELEASE_ID,
    timestamp: new Date().toISOString()
  });
});

// Chaos control endpoints
app.post('/chaos/start', (req, res) => {
  const mode = req.query.mode || 'error';
  chaosMode = true;
  chaosType = mode;
  res.json({ 
    message: 'Chaos mode started', 
    mode: mode,
    pool: APP_POOL 
  });
});

app.post('/chaos/stop', (req, res) => {
  chaosMode = false;
  chaosType = 'error';
  res.json({ 
    message: 'Chaos mode stopped',
    pool: APP_POOL 
  });
});

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`App (${APP_POOL}) listening on port ${PORT}`);
  console.log(`Release ID: ${RELEASE_ID}`);
});
