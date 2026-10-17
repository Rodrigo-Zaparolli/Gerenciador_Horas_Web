"""Dedicated percentage operation: never enter or save a comment."""
import sys
import traceback
from edesk_comentario import main

if __name__ == '__main__':
    try:
        sys.exit(main(percentage_only=True) or 0)
    except Exception:
        traceback.print_exc()
        sys.exit(1)
