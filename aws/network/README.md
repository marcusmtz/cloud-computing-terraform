# Red base de Norcom en AWS

Este primer módulo local prepara una VPC en dos zonas, con dos subredes de borde y dos privadas. Las privadas no reciben ruta a Internet; la VPC y el Internet Gateway se reservan como base para una implementación posterior de AD, API y persistencia.

La serie del proveedor AWS se limita a 6.x y el lockfile fija la versión 6.67.0 instalada el 30/09/2026. La validación de sintaxis local pasó con Terraform 1.16.4.

## Decisión técnica

- El reparto en dos zonas deja espacio para los dos controladores que AWS Managed Microsoft AD crea como mínimo y para un balanceador futuro.
- Las subredes privadas evitan exponer directamente datos y servicios internos. No se agrega NAT Gateway, balanceador, IP pública, instancia, base de datos ni directorio en esta fase.
- El bloque `10.42.0.0/16` evita los rangos `10.0.0.0/16` y `10.1.0.0/16` usados por otros entornos locales del proyecto; confirmar que no se superpone con redes VPN existentes antes de conectar sedes.
- Las subredes no asignan IPv4 pública automáticamente. No abrir CIDR de administración ni publicar puertos de base de datos en módulos posteriores.

## Costos y límites

AWS indica que la VPC y el Internet Gateway no tienen cargo de servicio; ciertos componentes sí cuestan, como NAT Gateway e IPv4 públicas. El tráfico por Internet también puede generar cargos. Este módulo no crea esos componentes facturables, aunque eso no sustituye la revisión de permisos y restricciones de Learner Lab. No ejecutar `apply` hasta que el alcance y el plan completo se revisen con el usuario.

Antes de añadir carga de trabajo se debe diseñar cómo administrarla y descargar actualizaciones sin una NAT de costo continuo. La elección entre endpoints privados, acceso temporal controlado u otra ruta depende de los servicios habilitados por Academy.

## Uso local

Ejecutar desde este directorio, una vez autorizada la inicialización del proveedor:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
& "../../../tools/terraform/terraform.exe" fmt -check -recursive
& "../../../tools/terraform/terraform.exe" init -backend=false
& "../../../tools/terraform/terraform.exe" validate
```

`init` descarga el proveedor HashiCorp AWS; requiere conexión de red. `validate` no despliega recursos, pero no consulta permisos/cuotas de la cuenta. Un `plan` con el proveedor configurado consulta AWS y se pospone hasta la siguiente puerta de auditoría/costo.

No almacenar credenciales, planes, estados, claves privadas ni archivos `.tfvars` reales en el repositorio. Los archivos de estado y planes pueden contener datos sensibles.
