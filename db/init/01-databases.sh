#!/bin/sh
# Bases y usuarios: una base por contexto, y un usuario que solo llega a la suya.
#
# MariaDB corre esto UNA sola vez, cuando el volumen esta vacio. No es "el paso de migracion" —
# el esquema lo aplica el migrador de cada servicio, que viaja dentro de su propia imagen. Aca
# solo existe lo que una API no puede crearse a si misma: su base y su credencial.
#
# Es un .sh y no un .sql porque el punto de entrada de MariaDB no sustituye variables dentro de un
# .sql, y las contrasenas tienen que venir del entorno y no del repositorio.
#
# Idempotente a proposito: agregar un contexto nuevo es agregar un bloque y correrlo a mano contra
# un volumen que ya existe. El release lo corre en cada despliegue, asi que el .env es la fuente de
# verdad: si cambia una contrasena o un usuario ya existia con otra, se alinea (ALTER USER) y se
# le quitan los permisos que tuviera antes de darle los suyos (REVOKE), de modo que un usuario
# nunca conserva acceso a la base de otro contexto.
set -eu

# Estos valores van dentro de un literal SQL y despues dentro de una cadena de conexion
# (Server=...;User=...;Password=...;), donde ; ' \" $ y espacios rompen en silencio. Mejor negarse.
check() {
  eval "v=\${$1:-}"
  case "$v" in
    ''|*[!A-Za-z0-9_.-]*)
      echo "init: $1 esta vacia o tiene caracteres no permitidos (solo letras, numeros, _ . -). Usar por ejemplo: openssl rand -hex 24" >&2
      exit 1 ;;
  esac
}
for n in PLATFORM PIMA TOURISM AUTOMOTIVE; do
  check "${n}_DB_NAME"; check "${n}_DB_USER"; check "${n}_DB_PASSWORD"
done

echo "init: creando bases y usuarios por contexto"

mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${PLATFORM_DB_NAME}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${PLATFORM_DB_USER}'@'%' IDENTIFIED BY '${PLATFORM_DB_PASSWORD}';
ALTER USER '${PLATFORM_DB_USER}'@'%' IDENTIFIED BY '${PLATFORM_DB_PASSWORD}';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${PLATFORM_DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${PLATFORM_DB_NAME}\`.* TO '${PLATFORM_DB_USER}'@'%';

CREATE DATABASE IF NOT EXISTS \`${PIMA_DB_NAME}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${PIMA_DB_USER}'@'%' IDENTIFIED BY '${PIMA_DB_PASSWORD}';
ALTER USER '${PIMA_DB_USER}'@'%' IDENTIFIED BY '${PIMA_DB_PASSWORD}';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${PIMA_DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${PIMA_DB_NAME}\`.* TO '${PIMA_DB_USER}'@'%';

CREATE DATABASE IF NOT EXISTS \`${TOURISM_DB_NAME}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${TOURISM_DB_USER}'@'%' IDENTIFIED BY '${TOURISM_DB_PASSWORD}';
ALTER USER '${TOURISM_DB_USER}'@'%' IDENTIFIED BY '${TOURISM_DB_PASSWORD}';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${TOURISM_DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${TOURISM_DB_NAME}\`.* TO '${TOURISM_DB_USER}'@'%';

CREATE DATABASE IF NOT EXISTS \`${AUTOMOTIVE_DB_NAME}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${AUTOMOTIVE_DB_USER}'@'%' IDENTIFIED BY '${AUTOMOTIVE_DB_PASSWORD}';
ALTER USER '${AUTOMOTIVE_DB_USER}'@'%' IDENTIFIED BY '${AUTOMOTIVE_DB_PASSWORD}';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${AUTOMOTIVE_DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${AUTOMOTIVE_DB_NAME}\`.* TO '${AUTOMOTIVE_DB_USER}'@'%';

FLUSH PRIVILEGES;
SQL

echo "init: listo — 4 bases, 4 usuarios, ninguno con acceso a la base de otro"
