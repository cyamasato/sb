openssl req -new -newkey rsa:2048 -nodes \
  -keyout traefik/certs/glpi.key -out glpi.csr \
  -subj "/CN=glpi.santosbrasil.com.br" \
  -addext "subjectAltName=DNS:glpi.santosbrasil.com.br,IP:10.89.2.122"
chmod 600 traefik/certs/glpi.key
cat glpi.csr
