
import secrets
import base64

def generate_secret_key():
    return base64.b64encode(secrets.token_bytes(32)).decode('utf-8')

print("Generated Secret Key:", generate_secret_key())
