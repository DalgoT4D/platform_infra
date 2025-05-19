module.exports = {
    interpreter: "/home/ddp/.nvm/versions/node/v18.20.3/bin/node",
    apps: [
        {
            max_restarts: 5,
            name: 'prefect-worker-ddp-1',
            script: 'PREFECT_API_URL="http://localhost:4200/api" /home/ddp/prefect-proxy/.venv/bin/prefect worker start --work-queue ddp --pool prod_dalgo_work_pool --limit 1',
        },
        {
            max_restarts: 5,
            name: 'prefect-worker-ddp-2',
            script: 'PREFECT_API_URL="http://localhost:4200/api" /home/ddp/prefect-proxy/.venv/bin/prefect worker start --work-queue ddp --pool prod_dalgo_work_pool --limit 1',
        },
        {
            max_restarts: 5,
            name: 'prefect-worker-ddp-3',
            script: 'PREFECT_API_URL="http://localhost:4200/api" /home/ddp/prefect-proxy/.venv/bin/prefect worker start --work-queue ddp --pool prod_dalgo_work_pool --limit 1',
        },
        {
            max_restarts: 5,
            name: 'prefect-worker-ddp-4',
            script: 'PREFECT_API_URL="http://localhost:4200/api" /home/ddp/prefect-proxy/.venv/bin/prefect worker start --work-queue ddp --pool prod_dalgo_work_pool --limit 1',
        },
        {
            max_restarts: 5,
            name: 'prefect-worker-manual-dbt-1',
            script: 'PREFECT_API_URL="http://localhost:4200/api" /home/ddp/prefect-proxy/.venv/bin/prefect worker start --work-queue manual-dbt --pool prod_dalgo_work_pool --limit 1',
        },
        {
            max_restarts: 5,
            name: 'prefect-worker-manual-dbt-2',
            script: 'PREFECT_API_URL="http://localhost:4200/api" /home/ddp/prefect-proxy/.venv/bin/prefect worker start --work-queue manual-dbt --pool prod_dalgo_work_pool --limit 1',
        },
        {
            max_restarts: 5,
            name: 'prefect-worker-manual-dbt-3',
            script: 'PREFECT_API_URL="http://localhost:4200/api" /home/ddp/prefect-proxy/.venv/bin/prefect worker start --work-queue manual-dbt --pool prod_dalgo_work_pool --limit 1',
        },
        {
            max_restarts: 5,
            name: 'prefect-worker-edr',
            script: 'PREFECT_API_URL="http://localhost:4200/api" /home/ddp/prefect-proxy/.venv/bin/prefect worker start --work-queue edr --pool prod_dalgo_work_pool --limit 1',
        },
        {
            max_restarts: 5,
            name: 'prefect-worker-dailybackup',
            script: 'PREFECT_API_URL="http://localhost:4200/api" /home/ddp/prefect-proxy/.venv/bin/prefect worker start --pool dailybackup --limit 1',
        },
        {
            max_restarts: 5,
            name: 'prefect-server',
            script: '/home/ddp/prefect-proxy/.venv/bin/prefect server start',
            env: {
                "GOOGLE_APPLICATION_CREDENTIALS": "/home/ddp/secrets/dummy.json"
            }
        },
        {
            max_restarts: 5,
            name: 'prefect-proxy',
            cwd: '/home/ddp/prefect-proxy',
            script:
                '/home/ddp/prefect-proxy/.venv/bin/gunicorn proxy.main:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8080',
        }
    ]
}
