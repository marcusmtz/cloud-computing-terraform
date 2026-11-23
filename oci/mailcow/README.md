# Infraestructura OCI para Mailcow de demostración

Este módulo crea una VM Ubuntu 24.04 ARM64 `VM.Standard.A1.Flex` (2 OCPU, 12 GB, 50 GB de arranque) en la región home `sa-vinhedo-1`, con VCN propia. No instala ni inicia Mailcow. La fase inicial permite SSH y HTTPS solo desde `admin_cidr`; no abre el puerto 25. Así se puede instalar, cambiar credenciales y configurar TLS antes de aceptar correo público.

El estado Terraform es independiente del bucket OCI. No mezclar ambos estados ni incluir este módulo en el comando U2 hasta comprobar su despliegue y costo. La VM usa una IP pública efímera; cuando esté lista se creará `mail.lab.example.invalid` en Cloudflare como **DNS only**. Si la IP cambia, actualizar DNS antes de usar el correo. El MX de `example.invalid` se conserva.

Variables requeridas: `compartment_ocid`, `availability_domain`, `ssh_public_key` y `admin_cidr`. No guardar llaves privadas ni credenciales de OCI en este directorio. Antes de aplicar, confirmar cuota libre A1 y capacidad Always Free. Después de configurar el servidor, activar `enable_public_mail` para HTTPS, HTTP de desafío TLS y SMTP entrante; `enable_mail_clients` abre 587/993 solo si se necesitan clientes externos. Las pruebas entre buzones mediante webmail pueden hacerse sin abrir 25.

El correo externo saliente usará un relay autenticado; OCI bloquea la salida directa TCP/25 por defecto. Mailcow, DNS, SPF/DKIM/DMARC, copias y restauración se validan en fases posteriores del [plan de dominio](../../../Docs/planificacion/PLAN_DOMINIO_Y_CORREO_2026-11-04.md).
