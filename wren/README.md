- Copy the .env.example to `.env`
- Copy .wrenrc.example to `.wrenrc`
- Generate a new random (user) uuid
- Update open ai key, correct `HOST_PORT` and USER_UUID
- Update the user uuid in `.wrenrc`
- You might need to update the `COMPOSE_PROJECT_NAME` and `PLATFORM` based on your setup
- Run `docker compose up -d` to bring wren up