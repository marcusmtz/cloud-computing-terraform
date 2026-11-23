output "instance_id" {
  value = oci_core_instance.mail.id
}

output "public_ip" {
  value = oci_core_instance.mail.public_ip
}

output "mail_hostname" {
  value = "mail.lab.example.invalid"
}
