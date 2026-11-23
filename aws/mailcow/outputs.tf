output "public_ip" {
  value = aws_eip.mail.public_ip
}

output "instance_id" {
  value = aws_instance.mail.id
}

output "mail_hostname" {
  value = "mail.${var.mail_domain}"
}

output "roundcube_url" {
  value = "https://mail.${var.mail_domain}/roundcube/"
}

output "mail_domain" {
  value = var.mail_domain
}
