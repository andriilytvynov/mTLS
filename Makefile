PROJECT := mtls
help:
	@echo "Available targets:"
	@echo "  help     Show this help message"
	@echo "  simple   Start the Docker Compose services with simple mTLS setup"
	@echo "  full     Start the Docker Compose services with full CA mTLS setup"
	@echo "  down     Stop the Docker Compose services"
	@echo "  test     Test mTLS connection from client to nginx"
	@echo ""
	@echo "Usage:"
	@echo "  make full test down"
	@echo "    - Sets up a full mTLS environment with proper CA structure"
	@echo "  make simple test down"
	@echo "    - Sets up a simple mTLS environment without CA structure"

simple:
	@echo "Starting client and setting up mTLS certificates..."
	@PROJECT=${PROJECT} \
	 docker compose up client --detach
	
	@echo "Generate Client CA pair..."
	@docker exec -ti ${PROJECT}-client bash -c '\
		openssl genrsa -out client-ca.key.pem 4096 && \
		openssl req -x509 -new -key client-ca.key.pem -sha256 -days 3650 -out client-ca.cert.pem -subj "/CN=CLIENT CA" '

	@echo "Generate Client pair signed by Client CA..."
	@docker exec -ti ${PROJECT}-client bash -c '\
		openssl genrsa -out client.key.pem 2048 && \
		openssl req -new -key client.key.pem -out client.csr -subj "/CN=Client" && \
		openssl x509 -req -in client.csr -CA client-ca.cert.pem -CAkey client-ca.key.pem -out client.cert.pem -days 365 -sha256 '

	@echo "Generate Server CA pair..."
	@docker exec -ti ${PROJECT}-client bash -c '\
		openssl genrsa -out server-ca.key.pem 4096 && \
		openssl req -x509 -new -key server-ca.key.pem -sha256 -days 3650 -out server-ca.cert.pem -subj "/CN=SERVER CA" '

	@echo "Generate Server pair signed by Server CA..."
	@echo "NOTE: CN equals server's hostname"
	@docker exec -ti ${PROJECT}-client bash -c '\
		openssl genrsa -out server.key.pem 2048 && \
		openssl req -new -key server.key.pem -out server.csr -subj "/CN=nginx" && \
		openssl x509 -req -in server.csr -CA server-ca.cert.pem -CAkey server-ca.key.pem -out server.cert.pem -days 365 -sha256 '

	@echo "Compiling CA-bundle..."
	@docker exec -ti ${PROJECT}-client bash -c '\
		cat client-ca.cert.pem server-ca.cert.pem > ca-bundle.cert.pem '
	
	@echo "Starting services..."
	@PROJECT=${PROJECT} \
	 docker compose up --detach

full:
	@echo "Starting client and setting up mTLS certificates..."
	@PROJECT=${PROJECT} \
	 docker compose up client --detach
	
	@echo "Setup default CA structure..."
	@docker exec -ti ${PROJECT}-client bash -c '\
		mkdir -p /opt/client-ca/newcerts && \
		touch /opt/client-ca/index.txt && \
		echo 1000 > /opt/client-ca/serial && \
		cp /usr/lib/ssl/openssl.cnf /opt/client-ca/openssl.cnf && \
		sed -i "s|^dir\s*=.*|dir = /opt/client-ca|g" /opt/client-ca/openssl.cnf && \
		mkdir -p /opt/server-ca/newcerts && \
		touch /opt/server-ca/index.txt && \
		echo 1000 > /opt/server-ca/serial && \
		cp /usr/lib/ssl/openssl.cnf /opt/server-ca/openssl.cnf && \
		sed -i "s|^dir\s*=.*|dir = /opt/server-ca|g" /opt/server-ca/openssl.cnf'

	@echo "Generate Client CA pair..."
	@docker exec -ti ${PROJECT}-client bash -c '\
		openssl genrsa -out client-ca.key.pem 4096 && \
		openssl req -x509 -new -key client-ca.key.pem -sha256 -days 3650 -out client-ca.cert.pem -subj "/CN=CLIENT CA/C=XX/ST=Xxx/O=XXXXX" '

	@echo "Generate Client pair signed by Client CA..."
	@docker exec -ti ${PROJECT}-client bash -c '\
		openssl genrsa -out client.key.pem 2048 && \
		openssl req -new -key client.key.pem -out client.csr -subj "/CN=Client/C=XX/ST=Xxx/O=XXXXX" && \
		openssl ca -in client.csr -out client.cert.pem -cert client-ca.cert.pem -keyfile client-ca.key.pem -batch -config /opt/client-ca/openssl.cnf '

	@echo "Generate Server CA pair..."
	@docker exec -ti ${PROJECT}-client bash -c '\
		openssl genrsa -out server-ca.key.pem 4096 && \
		openssl req -x509 -new -key server-ca.key.pem -sha256 -days 3650 -out server-ca.cert.pem -subj "/CN=SERVER CA/C=YY/ST=Yyy/O=YYYYY" '

	@echo "Generate Server pair signed by Server CA..."
	@echo "NOTE: CN equals server's hostname"
	@docker exec -ti ${PROJECT}-client bash -c '\
		openssl genrsa -out server.key.pem 2048 && \
		openssl req -new -key server.key.pem -out server.cert.pem -subj "/CN=nginx/C=YY/ST=Yyy/O=YYYYY" && \
		openssl ca -in server.cert.pem -out server.cert.pem -cert server-ca.cert.pem -keyfile server-ca.key.pem -batch -config /opt/server-ca/openssl.cnf '

	@echo "Compiling CA-bundle..."
	@docker exec -ti ${PROJECT}-client bash -c '\
		cat client-ca.cert.pem server-ca.cert.pem > ca-bundle.cert.pem '

	@echo "Starting services..."
	@PROJECT=${PROJECT} \
	 docker compose up --detach

down:
	@echo "Stopping services..."
	@PROJECT=${PROJECT} \
	 docker compose down -v && \
	 rm -rf ./mtls/*.pem ./mtls/*.csr

test:
	@echo "Testing mTLS connection from client to nginx..."
	@echo "NOTE: Sending request with client certificate and receiving response from backend with passed DN in the headers"
	@PROJECT=${PROJECT} \
	 docker exec -ti ${PROJECT}-client bash -c '\
		curl https://nginx/headers \
			--cert client.cert.pem \
			--key client.key.pem \
			--cacert ca-bundle.cert.pem '