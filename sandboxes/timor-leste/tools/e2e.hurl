# Test the Driver License service via X-Road Security Server
GET https://ss-oss:8443/r1/TL-TEST/GOV/MTC/DNTT/driver-license/v1/licenses/TL-12345
X-Road-Client: TL-TEST/GOV/OSS/PORTAL
[Options]
insecure: true

HTTP 200
[Asserts]
# Check that it actually passed through X-Road (Security Server injects this)
header "X-Road-Request-Id" exists


# Test the Birth Certificate service via X-Road Security Server
GET https://ss-oss:8443/r1/TL-TEST/GOV/MJ/JUSTICE/birth-certificate/v1/certificates/TL-67890
X-Road-Client: TL-TEST/GOV/OSS/PORTAL
[Options]
insecure: true

HTTP 200
[Asserts]
header "X-Road-Request-Id" exists
