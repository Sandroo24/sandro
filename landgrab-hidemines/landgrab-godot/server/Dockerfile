# Landgrab relay: no packages needed. Build: docker build -t landgrab-relay server   Run: docker run -p 8765:8765 landgrab-relay
FROM python:3.12-slim
WORKDIR /app
COPY relay.py check_server.py ./
ENV PORT=8765
EXPOSE 8765
CMD ["python", "-u", "relay.py"]
