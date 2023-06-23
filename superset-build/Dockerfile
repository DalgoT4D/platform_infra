FROM apache/superset

# Switching to root to install the required packages
USER root

# Example: installing the MySQL driver to connect to the metadata database
# if you prefer Postgres, you may want to use `psycopg2-binary` instead
RUN pip install --upgrade pip

RUN pip install psycopg2-binary

# https://superset.apache.org/docs/installation/alerts-reports/#custom-dockerfile
RUN apt-get update && \
  apt-get install --no-install-recommends -y firefox-esr wget

ENV GECKODRIVER_VERSION=0.29.0
RUN wget -q https://github.com/mozilla/geckodriver/releases/download/v${GECKODRIVER_VERSION}/geckodriver-v${GECKODRIVER_VERSION}-linux64.tar.gz && \
  tar -x geckodriver -zf geckodriver-v${GECKODRIVER_VERSION}-linux64.tar.gz -O > /usr/bin/geckodriver && \
  chmod 755 /usr/bin/geckodriver && \
  rm geckodriver-v${GECKODRIVER_VERSION}-linux64.tar.gz

RUN pip install --no-cache gevent psycopg2 redis flower



# Example: installing a driver to connect to Redshift
# Find which driver you need based on the analytics database
# you want to connect to here:
# https://superset.apache.org/installation.html#database-dependencies
# RUN pip install sqlalchemy-redshift

# Switching back to using the `superset` user
USER superset

COPY superset_config.py /app/superset/config.py
