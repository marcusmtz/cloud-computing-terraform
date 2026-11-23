# AWS V1 — catálogo web y PostgreSQL privado

Este root configura una prueba académica del catálogo público de Norcom, con datos ficticios: API Gateway HTTP API, Lambda Node.js 22, RDS PostgreSQL privado, secreto lector independiente y endpoint privado de Secrets Manager. Reutiliza la red de `../network`. No crea Managed AD, intranet, Mailcow, ALB, NAT Gateway, IP pública ni balanceador adicional.

## Seguridad y disponibilidad

- API Gateway entrega el endpoint HTTPS; CORS limita el origen de navegador configurado en `web_origin`. El frontend Azure actual consulta por el proxy Node del mismo origen, sin exponer credenciales o conexión a PostgreSQL en el navegador. El stage limita las solicitudes a 10 por segundo con ráfaga 20; la API Lambda queda limitada a cinco ejecuciones simultáneas.
- Las dos funciones corren en subredes privadas, sin ruta a Internet. La salida se limita a TCP 5432 en las dos subredes privadas y TCP 443 en la subred privada que aloja el endpoint de Secrets Manager; la base no tiene IP pública y solo acepta conexiones desde el grupo de Lambda.
- RDS cifra almacenamiento, administra la contraseña maestra en Secrets Manager, retiene backups automatizados un día y queda Single-AZ. El backup aporta recuperación limitada, no alta disponibilidad; en caso de caída, la base no hará failover automático. Al destruir la prueba se omite snapshot final porque solo contiene fixtures sintéticos.
- El endpoint de Secrets Manager usa una sola AZ para limitar el cargo horario. Es un punto único de acceso a secretos y deberá duplicarse en otra AZ si la fase productiva y el presupuesto requieren tolerancia a fallos.
- Por las restricciones de IAM del Learner Lab, ambas funciones usan el rol precreado `LabRole`; el laboratorio no permite crear los roles distintos de mínimo privilegio previstos para producción. Este rol compartido tiene permisos más amplios, así que la V1 queda limitada a datos sintéticos y no debe recibir datos personales. El permiso SQL del usuario de catálogo sí queda limitado a lectura de `public_listing_v1`.
- La función bootstrap no tiene ruta HTTP. Solo procesa `{ "confirm": "initialize-public-catalog" }`, crea el esquema y datos de demostración la primera vez y después crea/rota `norcom_catalog_reader`. Terraform no recibe contraseñas. Ambas funciones usan `NODE_EXTRA_CA_CERTS=/var/runtime/ca-cert.pem` para validar TLS hacia RDS con Node.js 22. El CORS desplegado permite `http://localhost:4200`; el portal de desarrollo en `127.0.0.1:4302` llega a AWS a través de su proxy local. Antes de publicar el portal separado hay que cambiar CORS al host HTTPS definitivo.
- Los grupos de logs de Lambda retienen tres días. No se exportan logs de PostgreSQL en esta V1 para evitar almacenamiento de logs no necesario.

La topología cubre una demostración pequeña y **no** cumple un objetivo de alta disponibilidad de producción. API Gateway puede responder a nivel de entrada administrado, pero la base Single-AZ y el endpoint de secretos en una AZ son puntos de falla. La arquitectura final evaluará RDS Multi-AZ/replicas, endpoints en dos zonas, redundancia de AD y balanceo/escala de aplicaciones en función de la rúbrica, mediciones y créditos confirmados.

## Costo y puerta de cuenta

Los componentes con consumo persistente son la instancia RDS mientras exista, sus 20 GiB, el backup de un día, el secreto lector, el endpoint de interfaz por hora/datos procesados y los logs de Lambda. API Gateway y Lambda dependen de solicitudes/tiempo de ejecución. El usuario confirmó Learner Lab activo y US$0,70 usados de US$50 antes del despliegue del 01/10/2026; el precio exacto de RDS y PrivateLink no pudo consultarse con el rol Academy. El crédito no equivale a gratuidad ni evita gasto fuera de créditos. Revisar el medidor ahora y en cada sesión; registrar la hora de fin, y preguntar antes de dejar recursos activos o destruirlos.

## Construcción y validación local

Desde la raíz del proyecto:

```powershell
./api/scripts/build-lambdas.ps1
Copy-Item terraform/aws/v1/terraform.tfvars.example terraform/aws/v1/terraform.tfvars
```

El portal Azure consulta la API por un proxy de mismo origen. La clase `db.t3.micro`, el motor y GP2 mínimo deben aparecer permitidos en el Learner Lab. No pongas secretos en ese archivo. Si se cambia el frontend para invocar API Gateway directamente, actualiza `web_origin` al host HTTPS exacto.

Desde `terraform/aws/v1`, inicializa Terraform y valida HCL:

```powershell
& "../../../tools/terraform/terraform.exe" init -backend=false
& "../../../tools/terraform/terraform.exe" fmt -check -recursive
& "../../../tools/terraform/terraform.exe" validate
```

`init` puede necesitar descargar el provider si no está en la caché local. Un `plan` consulta la cuenta AWS y no crea recursos. Antes de `apply`, verificar sesión activa, saldo vigente, permisos, cuotas, costo total y ventana de limpieza.

## Despliegue V1 ejecutado el 01/10/2026

1. El plan remoto con `LabRole` propuso 32 altas, cero cambios y cero eliminaciones.
2. Terraform aplicó red, RDS, endpoint privado, API Gateway, dos funciones Lambda, secretos y logs; las iteraciones posteriores solo modificaron las funciones para habilitar CA TLS y el grupo de seguridad de Lambda para restablecer las dos salidas privadas. No se creó ni borró ningún recurso en esas iteraciones.
3. La invocación manual y confirmada de `catalog-bootstrap` respondió `initialized`; instaló la vista y seis fixtures sintéticos, y generó la credencial lectora independiente.
4. `GET /healthz` respondió `ok`/`available`; el listado devolvió seis resultados (dos en la página de prueba) y el detalle de una publicación coincidió con el identificador solicitado.
5. El portal local `web-projects/portal-inmobiliario` consulta la API a través del proxy de desarrollo; sus 4 pruebas y la compilación de producción pasaron. El endpoint CORS de Azure y su publicación siguen pendientes. Evidencia sin credenciales: `Docs/evidencias/aws_v1_despliegue_2026-10-01.md`. Consultar el saldo Academy actualizado y decidir con el usuario si se mantiene el entorno por una ventana concreta para publicar el portal o se revisa y aplica un `terraform destroy`. No dejarlo activo sin confirmar la ventana.
# AWS Managed Microsoft AD (plan local, todavía no aplicado)

`directory.tf` define un directorio AWS Managed Microsoft AD Standard para el dominio privado `ad.norcom.test` en las dos subredes privadas existentes de Norcom (`us-east-1a` y `us-east-1b`). AWS Managed Microsoft AD necesita subredes en dos zonas y entrega dos controladores administrados; este dominio separa cuentas internas de las identidades de clientes del portal. El sufijo `.test` es para el laboratorio y no proporciona correo ni DNS público.

La consulta de solo lectura del 01/10/2026 encontró cero directorios en uso y cuota Directory Service `ManagedADLimit=20`. También confirmó que las subredes privadas `10.42.0.0/20` y `10.42.16.0/20` están en zonas distintas. Esto confirma topología/cuota regional, **no** confirma permiso efectivo de creación ni gratuidad/cobertura del crédito Academy. Ver `Docs/cuentas/aws_academy.md`.

No aplicar aún: comprobar en Learner Lab elegibilidad/costo de Managed AD, el saldo después de cualquier consumo y la ventana autorizada. AWS publica 1.500 horas de controlador de prueba limitada, sujeta a elegibilidad de nuevo cliente; el directorio estándar usa dos controladores. El ejemplo oficial de tarifa posterior es USD 0,40/hora por directorio en Ohio (aprox. USD 9,60/día a 24x7); validar precio de us-east-1 y si Academy participa. Si no aplica la prueba, el crédito AWS reportado podría consumirse en pocos días. El directorio contiene credenciales privilegiadas. La documentación del proveedor Terraform advierte que la contraseña queda en texto claro en el state, aunque la variable sea sensible. Nunca crear o compartir `terraform.tfvars`, archivo de plan ni state con contraseñas; antes de un `apply` resolver cifrado del state y gestión de credenciales. El ciclo de vida `prevent_destroy` evita borrar AD por error; solo se retirará después de la autorización explícita del usuario.

Para preparar un plan en una sesión privada, configurar `TF_VAR_ad_admin_password` en el entorno local (no en texto de comando ni en un archivo compartido) y ejecutar `terraform plan` desde esta carpeta. No guardar el plan binario. Revisar que el único cambio previsto sea `aws_directory_service_directory.norcom`; detenerse si propone cambios o destrucciones en recursos V1 existentes.
