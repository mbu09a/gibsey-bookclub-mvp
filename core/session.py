from itsdangerous import TimestampSigner
from typing import Optional

# TODO: Move this to an environment variable
SECRET_KEY = "SUPER-SECRET-KEY"
SIGNER = TimestampSigner(SECRET_KEY)
COOKIE_MAX_AGE_SECONDS = 60 * 60 * 24 * 7  # 7 days

def make_cookie(user_id: int) -> str:
    """Creates a signed cookie string for the given user ID."""
    return SIGNER.sign(str(user_id).encode('utf-8')).decode('utf-8')

def verify_cookie(cookie_value: str) -> Optional[int]:
    """Verifies a signed cookie string and returns the user ID if valid, otherwise None."""
    if not cookie_value:
        return None
    try:
        user_id_bytes = SIGNER.unsign(cookie_value.encode('utf-8'), max_age=COOKIE_MAX_AGE_SECONDS)
        return int(user_id_bytes.decode('utf-8'))
    except Exception:  # Catches BadSignature, SignatureExpired, etc.
        return None 