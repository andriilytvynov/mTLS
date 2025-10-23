PROJECT := mtls
help:
	@echo "Available targets:"
	@echo "  help	Show this help message"
	@echo "  up		Start the Docker Compose services"
	@echo "  down	Stop the Docker Compose services"
	@echo "  test 	Test mTLS connection from client to nginx"
	@echo ""

up:
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
		openssl req -new -key client.key.pem -out client.cert.pem -subj "/CN=Client" && \
		openssl x509 -req -in client.cert.pem -CA client-ca.cert.pem -CAkey client-ca.key.pem -CAcreateserial -out client-signed.cert.pem -days 365 -sha256 '
	
	@echo "Generate Server CA pair..."
	@docker exec -ti ${PROJECT}-client bash -c '\
		openssl genrsa -out server-ca.key.pem 4096 && \
		openssl req -x509 -new -key server-ca.key.pem -sha256 -days 3650 -out server-ca.cert.pem -subj "/CN=SERVER CA" '
	
	@echo "Generate Server pair signed by Server CA..."
	@echo "NOTE: CN equals server's hostname"
	@docker exec -ti ${PROJECT}-client bash -c '\
		openssl genrsa -out server.key.pem 2048 && \
		openssl req -new -key server.key.pem -out server.cert.pem -subj "/CN=nginx" && \
		openssl x509 -req -in server.cert.pem -CA server-ca.cert.pem -CAkey server-ca.key.pem -CAcreateserial -out server-signed.cert.pem -days 365 -sha256 '

	@echo "Compiling CA-bundle..."
	@docker exec -ti ${PROJECT}-client bash -c '\
		cat client-ca.cert.pem server-ca.cert.pem > ca-bundle.cert.pem '
	
	@echo "Starting services..."
	@PROJECT=${PROJECT} \
	 docker compose up --detach

down:
	@echo "Stopping services..."
	@PROJECT=${PROJECT} \
	 docker compose down -v

test:
	@echo "Testing mTLS connection from client to nginx..."
	@echo "NOTE: Sending request with client certificate and receiving response from backend with passed DN in the headers"
	@PROJECT=${PROJECT} \
	 docker exec -ti ${PROJECT}-client bash -c '\
		curl https://nginx/headers \
			--cert client-signed.cert.pem \
			--key client.key.pem \
			--cacert ca-bundle.cert.pem '