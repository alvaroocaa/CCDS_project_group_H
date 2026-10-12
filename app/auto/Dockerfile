FROM python:3.12-alpine
WORKDIR /srv
COPY feeder.py .
RUN adduser -D bot
USER bot
CMD ["python", "feeder.py"]
