# Declarative audit device. OpenBao 2.7.2 refuses to enable audit devices through the API
# ("use declarative, config-based audit device management instead"), so it lives here.
# mode 0644 so the ClickHouse container can read the file through the shared volume (lab only).
audit "file" "file" {
  description = "Every request and response, one JSON object per line."
  options {
    file_path = "/openbao/logs/audit.log"
    mode      = "0644"
  }
}
