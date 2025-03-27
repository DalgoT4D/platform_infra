module.exports = {
  apps: [
    {
      max_restarts: 5,
      name: 'django-celery-worker',
      cwd: '/home/ddp/DDP_backend',
      script:
        '/home/ddp/DDP_backend/.venv/bin/celery -A ddpui worker -n ddpui --pidfile /home/ddp/DDP_backend/celeryworker.pid',
    },
    {
      max_restarts: 5,
      name: 'django-celery-beat',
      cwd: '/home/ddp/DDP_backend',
      script:
        '/home/ddp/DDP_backend/.venv/bin/celery -A ddpui beat --pidfile /home/ddp/DDP_backend/celerybeat.pid',
    },
    {
      max_restarts: 5,
      name: 'django-backend-asgi',
      cwd: '/home/ddp/DDP_backend',
      script:
        '/home/ddp/DDP_backend/.venv/bin/uvicorn ddpui.asgi:application --workers 4 --host 0.0.0.0 --port 8002 --timeout-keep-alive 60',
    },
    {
      max_restarts: 5,
      name: 'ddp-webapp',
      script: 'yarn start',
      cwd: '/home/ddp/webapp',
    },
  ],
};
