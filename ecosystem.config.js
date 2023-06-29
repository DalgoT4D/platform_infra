module.exports = {
  apps: [
    {
      name: 'prefect-agent',
      script: '/home/ddp/venv/bin/prefect agent start -q ddp',
    },
    {
      name: 'prefect-server',
      script: '/home/ddp/venv/bin/prefect server start',
    },
    {
      name: 'prefect-proxy',
      script:
        '/home/ddp/prefect-proxy/venv/bin/gunicorn proxy.main:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8080',
    },
    {
      name: 'django-celery-worker',
      script:
        '/home/ddp/DDP_backend/venv/bin/celery -A ddpui worker -n /home/ddp/DDP_backend --pidfile /home/ddp/DDP_backend/celeryworker.pid',
    },
    {
      name: 'django-backend',
      script:
        '/home/ddp/DDP_backend/venv/bin/gunicorn -b localhost:8002 ddpui.wsgi --capture-output --log-config /home/ddp/DDP_backend/gunicorn-log.conf',
    },
    {
      name: 'ddp-webapp',
      script: 'yarn start',
      cwd: '/home/ddp/webapp',
    },
  ],
};
