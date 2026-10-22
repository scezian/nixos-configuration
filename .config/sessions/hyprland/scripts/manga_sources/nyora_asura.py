import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _nyora_core as c


class Source(c.Source):
    ID = "NYORA_ASURA"
    NAME = "Asura Scans"
    SRC = "ASURASCANS"
