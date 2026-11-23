# OCI Object Storage — respaldo Norcom

Este root Terraform administra el bucket privado `norcom-academic-backups-202610` en la home region `sa-vinhedo-1`, como destino de copias cifradas fuera de AWS. Ya se aplicó un plan de una creación, cero cambios y cero destrucciones. El bucket usa cifrado AES-256 del lado del servicio con clave administrada por Oracle; el acceso anónimo está deshabilitado, el versionado permanece apagado para evitar crecimiento inadvertido y no se configuró retención inmutable que impida borrar datos de prueba. No contiene credenciales ni configura usuarios de IAM.

## Límite de alcance actual

La instancia PostgreSQL activa está en subredes privadas AWS sin NAT y Learner Lab bloquea actualmente las consultas necesarias de EC2/Directory Service con `voc-cancel-cred`. Por ello, todavía no se puede ejecutar un `pg_dump` completo ni habilitar de forma segura una ruta desde AWS hacia OCI. El futuro respaldo de base deberá generarse dentro de la VPC o a través de un canal privado/autorizado, cifrarse y transferirse a OCI; una exportación del endpoint público de catálogo sirve como prueba académica de flujo entre nubes, pero **no** se debe llamar backup completo de RDS ni ERP.

## Costos y control

Mantener bucket y datos por debajo del límite Always Free aplicable. OCI publica 10 GB de almacenamiento Standard Always Free durante una cuenta de prueba/créditos (y hasta 20 GB combinados después de pasar a Always Free), además de 50.000 solicitudes API mensuales. Los datos fuera de la asignación y las operaciones fuera del alcance elegible pueden consumir crédito; comprobar en consola que la instancia/métrica aparece elegible y mantener un límite operativo propio de 10 MB para artefactos académicos. No usar Archive ni llave Vault propia en esta primera prueba.

## Validación y ejecución

1. Confirmar perfil OCI `DEFAULT`, región home `sa-vinhedo-1`, OCID del compartimento y namespace; no copiar el contenido de `~/.oci/config` ni la clave privada.
2. Copiar `terraform.tfvars.example` a `terraform.tfvars` y completar los dos valores localmente. El archivo de variables está excluido de Git.
3. Ejecutar `terraform init`, `terraform fmt -check -recursive`, `terraform validate` y revisar `terraform plan`.
4. Aplicar solo el bucket previsto; el plan debe mostrar exactamente una creación y ningún cambio o borrado.
5. Verificar `NoPublicAccess`, cifrado predeterminado, almacenamiento usado y luego probar put/get de un JSON sintético pequeño.

La prueba `scripts/oci/backup-public-catalog.ps1` ya transfirió y recuperó las seis publicaciones sintéticas expuestas públicamente por la API AWS (2.628 bytes; SHA-256 coincidente). No es una copia de RDS. La copia de datos personales o credenciales queda prohibida. La recuperación real de RDS, ERP y buzones requiere diseñar y probar aparte el formato, la conectividad, IAM de mínimo privilegio, retención, integridad y procedimiento de restore. Ver `Docs/evidencias/oci_respaldo_catalogo_2026-10-01.md`.

## Dump PostgreSQL local para desarrollo

`scripts/oci/backup-local-postgres.ps1` prepara un dump lógico en formato custom del contenedor Docker `norcom-postgres`, lo valida con `pg_restore --list`, lo sube al bucket privado y lo descarga de vuelta para comparar SHA-256. El archivo se limita a 10 MiB por defecto y se conserva en `Backups/oci/`. OCI cifra objetos en reposo con la clave administrada por Oracle. El script no vuelca secretos, no cambia la base de origen y no restaura sobre ella.

Esta ruta es para la base **local de desarrollo**, no para el RDS privado de AWS. La ejecución del 01/10/2026 creó un objeto de 33.833 bytes, lo descargó y verificó SHA-256; ver `Docs/evidencias/oci_respaldo_postgres_local_2026-10-01.md`. La restauración a una instancia PostgreSQL aislada queda como siguiente validación. El script resuelve también la ruta de Docker Desktop instalada por usuario, para que no dependa de que `docker` ya esté en el `PATH` del terminal de Codex. Ejecútalo desde la raíz del proyecto con Docker Desktop activo y OCI CLI autenticada:

```powershell
./scripts/oci/backup-local-postgres.ps1
```

Usar solamente fixtures sintéticos. No subir contraseñas, datos personales ni copias de producción a este bucket académico.
