"""Print a random secret suitable for JWT_SECRET in backend/.env."""
import secrets

if __name__ == "__main__":
    print(secrets.token_hex(32))
