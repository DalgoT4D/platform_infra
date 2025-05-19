import os
from cachelib.redis import RedisCache
from superset.superset_typing import CacheConfig
from celery.schedules import crontab
from flask_appbuilder.security.manager import AUTH_OAUTH
from superset.custom_user import CustomSecurityManager

import client_color_palettes

CUSTOM_SECURITY_MANAGER = CustomSecurityManager

SQLALCHEMY_DATABASE_URI = os.environ["SQLALCHEMY_DATABASE_URI"]
FEATURE_FLAGS = {
    "ENABLE_TEMPLATE_PROCESSING": True,
    "ALERT_REPORTS": True,
    "DASHBOARD_CROSS_FILTERS": True,
    "DASHBOARD_RBAC": True,
    "DRILL_TO_DETAIL": True,
    "HORIZONTAL_FILTER_BAR": True,
    "ESTIMATE_QUERY_COST": True,
    "SSH_TUNNELING": True,
}

# Default cache for Superset objects
CACHE_CONFIG: CacheConfig = {
    "CACHE_DEFAULT_TIMEOUT": 3600,
    # should the timeout be reset when retrieving a cached value
    "REFRESH_TIMEOUT_ON_RETRIEVAL": True,
    "CACHE_TYPE": "RedisCache",
    "CACHE_KEY_PREFIX": "superset_results",
    "CACHE_REDIS_URL": os.environ["BROKER_URL"],
}

# Cache for datasource metadata and query results
DATA_CACHE_CONFIG: CacheConfig = {
    "CACHE_DEFAULT_TIMEOUT": 3600,
    # should the timeout be reset when retrieving a cached value
    "REFRESH_TIMEOUT_ON_RETRIEVAL": True,
    "CACHE_TYPE": "RedisCache",
    "CACHE_KEY_PREFIX": "superset_data_cache",
    "CACHE_REDIS_URL": os.environ["BROKER_URL"],
}

# Cache for dashboard filter state (`CACHE_TYPE` defaults to `SimpleCache` when
#  running in debug mode unless overridden)
FILTER_STATE_CACHE_CONFIG: CacheConfig = {
    "CACHE_DEFAULT_TIMEOUT": 3600,
    # should the timeout be reset when retrieving a cached value
    "REFRESH_TIMEOUT_ON_RETRIEVAL": True,
    "CACHE_TYPE": "RedisCache",
    "CACHE_KEY_PREFIX": "superset_filter_cache",
    "CACHE_REDIS_URL": os.environ["BROKER_URL"],
}

# Cache for explore form data state (`CACHE_TYPE` defaults to `SimpleCache` when
#  running in debug mode unless overridden)
EXPLORE_FORM_DATA_CACHE_CONFIG: CacheConfig = {
    "CACHE_DEFAULT_TIMEOUT": 3600,
    # should the timeout be reset when retrieving a cached value
    "REFRESH_TIMEOUT_ON_RETRIEVAL": True,
    "CACHE_TYPE": "RedisCache",
    "CACHE_KEY_PREFIX": "superset_explore_form_data_cache",
    "CACHE_REDIS_URL": os.environ["BROKER_URL"],
}


REDIS_HOST = os.environ["REDIS_HOST"]
REDIS_PORT = "6379"


class CeleryConfig:  # pylint: disable=too-few-public-methods
    broker_url = os.environ["BROKER_URL"]
    imports = (
        "superset.sql_lab",
        "superset.tasks",
    )
    result_backend = os.environ["BROKER_URL"]
    worker_log_level = "DEBUG"
    worker_prefetch_multiplier = 10
    task_acks_late = True
    task_annotations = {
        "sql_lab.get_sql_results": {
            "rate_limit": "100/s",
        },
        "email_reports.send": {
            "rate_limit": "1/s",
            "time_limit": 120,
            "soft_time_limit": 150,
            "ignore_result": True,
        },
    }
    beat_schedule = {
        "email_reports.schedule_hourly": {
            "task": "email_reports.schedule_hourly",
            "schedule": crontab(minute=1, hour="*"),
        },
        # https://superset.apache.org/docs/installation/alerts-reports/
        "reports.scheduler": {
            "task": "reports.scheduler",
            "schedule": crontab(minute="*", hour="*"),
        },
    }


CELERY_CONFIG = CeleryConfig  # pylint: disable=invalid-name


RESULTS_BACKEND = RedisCache(
    host=os.environ["REDIS_HOST"], port=6379, key_prefix="superset_results"
)


EMAIL_NOTIFICATIONS = True
SMTP_HOST = os.environ["SMTP_HOST"]
SMTP_PORT = os.environ["SMTP_PORT"]
SMTP_STARTTLS = True
SMTP_SSL = False
SMTP_USER = os.environ["SMTP_USER"]
SMTP_PASSWORD = os.environ["SMTP_PASSWORD"]
SMTP_MAIL_FROM = os.environ["SMTP_MAIL_FROM"]
SMTP_SSL_SERVER_AUTH = False

WEBDRIVER_BASEURL = "http://superset-dalgo_superset-prod-4:8088/"

ENABLE_CORS = True
CORS_OPTIONS = {
    "supports_credentials": True,
    "allow_headers": [
        "X-CSRFToken",
        "Content-Type",
        "Origin",
        "X-Requested-With",
        "Accept",
        "Authorization",
        "X-Frame-Options",
    ],
    "origins": [os.environ["CORS_ORIGINS"].split(",")],
}

SESSION_COOKIE_SAMESITE = None
SESSION_COOKIE_SECURE = False
SUPERSET_FEATURE_EMBEDDED_SUPERSET = True
HTML_SANITIZATION = False

if os.getenv("ENABLE_OAUTH"):
    CSRF_ENABLED = True
    # change from AUTH_DB to AUTH_OAUTH
    AUTH_TYPE = AUTH_OAUTH

    # Will allow user self registration, allowing to create Flask users from Authorized User
    AUTH_USER_REGISTRATION = True

    # The default user self registration role
    AUTH_USER_REGISTRATION_ROLE = "Gamma"

    # without this the redirect_url will be "http" and will therefore not match the url
    # provided in the google cloud console
    ENABLE_PROXY_FIX = True

    GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID")
    GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET")
    GOOGLE_WHITELISTED_DOMAIN = os.getenv("GOOGLE_WHITELISTED_DOMAIN")

    # whitelist ourselves so our clients don't need to create accounts for us on their domain
    whitelist = ["@projecttech4dev.org"]
    if GOOGLE_WHITELISTED_DOMAIN and GOOGLE_WHITELISTED_DOMAIN != "projecttech4dev.org":
        whitelist.append("@" + GOOGLE_WHITELISTED_DOMAIN)

    OAUTH_PROVIDERS = [
        {
            "name": "google",
            "whitelist": whitelist,
            "token_key": "access_token",  # Name of the token in the response of access_token_url
            "icon": "fa-address-card",  # Icon for the provider
            "remote_app": {
                "client_id": GOOGLE_CLIENT_ID,  # Client Id (Identify Superset application)
                "client_secret": GOOGLE_CLIENT_SECRET,  # Secret for this Client Id (Identify Superset application)
                "client_kwargs": {"scope": "email"},  # Scope for the Authorization
                "access_token_method": "POST",  # HTTP Method to call access_token_url
                "access_token_params": {  # Additional parameters for calls to access_token_url
                    "client_id": GOOGLE_CLIENT_ID
                },
                "access_token_headers": {  # Additional headers for calls to access_token_url
                    "Authorization": "Basic Base64EncodedClientIdAndSecret"
                },
                "api_base_url": "https://www.googleapis.com/oauth2/v2/'",
                "access_token_url": "https://oauth2.googleapis.com/token",
                "authorize_url": "https://accounts.google.com/o/oauth2/auth",
            },
        }
    ]


MAPBOX_API_KEY = os.getenv("MAPBOX_API_KEY")

# https://superset.apache.org/docs/security/#content-security-policy-csp
TALISMAN_ENABLED = True
app_host = os.getenv("APPLICATION_HOST")
TALISMAN_CONFIG = {
    "force_https": False,  # because enabling this will break automated reports
    "content_security_policy": {
        "style-src": ["'self'", app_host, "'unsafe-inline'"],
        "img-src": ["'self'", app_host, "data:"],
        "worker-src": ["'self'", app_host, "blob:"],
        "connect-src": [
            "'self'",
            app_host,
            "https://api.mapbox.com",
            "https://events.mapbox.com",
        ],
        "frame-ancestors": [
            "self",
            "http://localhost:3000",
            "https://staging.dalgo.org",
            "https://dashboard.dalgo.org",
        ],
    },
}

# Branding
if os.environ.get("APP_NAME"):
    APP_NAME = os.environ.get("APP_NAME")

if os.environ.get("OVERRIDE_APP_ICON"):
    APP_ICON = "/static/assets/images/logo.png"

if os.environ.get("CUSTOM_COLOR_PALETTE"):
    EXTRA_CATEGORICAL_COLOR_SCHEMES = client_color_palettes.PALETTES[
        os.environ.get("CUSTOM_COLOR_PALETTE")
    ]
