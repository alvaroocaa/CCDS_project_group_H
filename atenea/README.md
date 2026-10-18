# Moodle Installation Wizard

## Step 1: Build and Run

```bash
docker compose up --build
```

Open Moodle in your browser:

```
http://localhost:8083
```

---

## Step 2: Moodle Setup

Click **Next** until you reach the **Database driver** page.

Select:

```
MariaDB (native/mariadb)
```

Click **Next**.

---

## Step 3: Database Settings

Use the following configuration:

```text
Database host: mariadb
Database name: moodle
Database user: moodle_user
Database password: moodle_password
```

Click **Next**.

---

## Step 4: Finish Installation

Continue clicking **Next** until the installation completes.

✅ Moodle should now be running successfully.

---

## Next Steps

Proceed with Moodle configuration as desired.

The remaining Moodle setup is not required for this project.
```
