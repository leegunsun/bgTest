// PM2 Ecosystem Configuration for Blue-Green Deployment
// 4 Application Instances per EC2 Instance

module.exports = {
  apps: [
    // Application Instance 1
    {
      name: 'bluegreen-app-1',
      script: './app-server/app.js',
      instances: 1,
      exec_mode: 'fork',
      env: {
        SERVER_PORT: 3001,
        ENV_NAME: process.env.DEPLOYMENT_GROUP || 'blue',
        VERSION: process.env.DEPLOYMENT_VERSION || '1.0.0',
        DEPLOYMENT_ID: process.env.DEPLOYMENT_ID || 'pm2-instance-1',
        COLOR_THEME: process.env.DEPLOYMENT_GROUP || 'blue',
        NODE_OPTIONS: '--max-old-space-size=120',
        NODE_ENV: 'production'
      },
      env_production: {
        NODE_ENV: 'production',
        SERVER_PORT: 3001
      },
      env_staging: {
        NODE_ENV: 'staging',
        SERVER_PORT: 3001
      },
      // Process management (Enhanced with graceful shutdown)
      min_uptime: '10s',
      max_restarts: 5,
      restart_delay: 2000,
      kill_timeout: 5000,
      listen_timeout: 10000,
      kill_retry_time: 100,
      
      // Graceful shutdown configuration
      shutdown_with_message: false,
      wait_ready: true,
      
      // Logging
      log_file: '/opt/bluegreen-app/logs/app-1.log',
      out_file: '/opt/bluegreen-app/logs/app-1-out.log',
      error_file: '/opt/bluegreen-app/logs/app-1-error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      
      // Health monitoring
      health_check_interval: 30000,
      
      // Resource limits
      max_memory_restart: '150M'
    },
    
    // Application Instance 2
    {
      name: 'bluegreen-app-2',
      script: './app-server/app.js',
      instances: 1,
      exec_mode: 'fork',
      env: {
        SERVER_PORT: 3002,
        ENV_NAME: process.env.DEPLOYMENT_GROUP || 'blue',
        VERSION: process.env.DEPLOYMENT_VERSION || '1.0.0',
        DEPLOYMENT_ID: process.env.DEPLOYMENT_ID || 'pm2-instance-2',
        COLOR_THEME: process.env.DEPLOYMENT_GROUP || 'blue',
        NODE_OPTIONS: '--max-old-space-size=120',
        NODE_ENV: 'production'
      },
      env_production: {
        NODE_ENV: 'production',
        SERVER_PORT: 3002
      },
      env_staging: {
        NODE_ENV: 'staging',
        SERVER_PORT: 3002
      },
      
      min_uptime: '10s',
      max_restarts: 5,
      restart_delay: 2000,
      kill_timeout: 5000,
      listen_timeout: 10000,
      kill_retry_time: 100,
      
      // Graceful shutdown configuration
      shutdown_with_message: false,
      wait_ready: true,
      
      log_file: '/opt/bluegreen-app/logs/app-2.log',
      out_file: '/opt/bluegreen-app/logs/app-2-out.log',
      error_file: '/opt/bluegreen-app/logs/app-2-error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      
      health_check_interval: 30000,
      max_memory_restart: '150M'
    },
    
    // Application Instance 3
    {
      name: 'bluegreen-app-3',
      script: './app-server/app.js',
      instances: 1,
      exec_mode: 'fork',
      env: {
        SERVER_PORT: 3003,
        ENV_NAME: process.env.DEPLOYMENT_GROUP || 'blue',
        VERSION: process.env.DEPLOYMENT_VERSION || '1.0.0',
        DEPLOYMENT_ID: process.env.DEPLOYMENT_ID || 'pm2-instance-3',
        COLOR_THEME: process.env.DEPLOYMENT_GROUP || 'blue',
        NODE_OPTIONS: '--max-old-space-size=120',
        NODE_ENV: 'production'
      },
      env_production: {
        NODE_ENV: 'production',
        SERVER_PORT: 3003
      },
      env_staging: {
        NODE_ENV: 'staging',
        SERVER_PORT: 3003
      },
      
      min_uptime: '10s',
      max_restarts: 5,
      restart_delay: 2000,
      kill_timeout: 5000,
      listen_timeout: 10000,
      kill_retry_time: 100,
      
      // Graceful shutdown configuration
      shutdown_with_message: false,
      wait_ready: true,
      
      log_file: '/opt/bluegreen-app/logs/app-3.log',
      out_file: '/opt/bluegreen-app/logs/app-3-out.log',
      error_file: '/opt/bluegreen-app/logs/app-3-error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      
      health_check_interval: 30000,
      max_memory_restart: '150M'
    },
    
    // Application Instance 4
    {
      name: 'bluegreen-app-4',
      script: './app-server/app.js',
      instances: 1,
      exec_mode: 'fork',
      env: {
        SERVER_PORT: 3004,
        ENV_NAME: process.env.DEPLOYMENT_GROUP || 'blue',
        VERSION: process.env.DEPLOYMENT_VERSION || '1.0.0',
        DEPLOYMENT_ID: process.env.DEPLOYMENT_ID || 'pm2-instance-4',
        COLOR_THEME: process.env.DEPLOYMENT_GROUP || 'blue',
        NODE_OPTIONS: '--max-old-space-size=120',
        NODE_ENV: 'production'
      },
      env_production: {
        NODE_ENV: 'production',
        SERVER_PORT: 3004
      },
      env_staging: {
        NODE_ENV: 'staging',
        SERVER_PORT: 3004
      },
      
      min_uptime: '10s',
      max_restarts: 5,
      restart_delay: 2000,
      kill_timeout: 5000,
      listen_timeout: 10000,
      kill_retry_time: 100,
      
      // Graceful shutdown configuration
      shutdown_with_message: false,
      wait_ready: true,
      
      log_file: '/opt/bluegreen-app/logs/app-4.log',
      out_file: '/opt/bluegreen-app/logs/app-4-out.log',
      error_file: '/opt/bluegreen-app/logs/app-4-error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      
      health_check_interval: 30000,
      max_memory_restart: '150M'
    }
  ],

  deploy: {
    production: {
      user: 'ec2-user',
      host: ['localhost'],
      ref: 'origin/main',
      repo: 'git@github.com:username/repo.git',
      path: '/opt/bluegreen-app',
      'pre-deploy-local': '',
      'post-deploy': 'npm install && pm2 reload ecosystem.config.js --env production',
      'pre-setup': ''
    },
    
    staging: {
      user: 'ec2-user', 
      host: ['localhost'],
      ref: 'origin/develop',
      repo: 'git@github.com:username/repo.git',
      path: '/opt/bluegreen-app-staging',
      'post-deploy': 'npm install && pm2 reload ecosystem.config.js --env staging',
      env: {
        NODE_ENV: 'staging'
      }
    }
  },

  // PM2+ Monitoring configuration (optional)
  monitoring: {
    // Enable PM2+ monitoring
    pmx: true,
    
    // Custom metrics
    network: true,
    ports: true,
    
    // Exception handling
    exceptions: true,
    
    // Custom actions
    actions: true
  }
};