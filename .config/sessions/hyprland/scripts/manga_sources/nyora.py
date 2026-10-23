# Registers one Nyora source per enabled id (Settings > Sources > Extensions).
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _nyora_core import make_sources  # noqa: F401
