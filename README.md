# CCDS_project_group_H
CCDS project group H

## Atenea / Moodle Stack

The Atenea stack provides a containerized Moodle LMS installation running on Apache/PHP and connected to a MariaDB database.

During the implementation:
- Moodle 5.3 is automatically downloaded during the Docker build process.
- PHP requirements and extensions are installed automatically.
- Database connectivity is configured through Docker Compose.
- Unicode and UTF-8 compatibility issues were resolved using MariaDB utf8mb4 configuration.
- No manual download or installation of Moodle source files is required.

Deployment only requires building the Docker image and running the compose file. After deployment, the Moodle web installation wizard can be completed through the browser.
