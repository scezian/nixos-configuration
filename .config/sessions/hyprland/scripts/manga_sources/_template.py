# Template for a custom manga source. Copy to manga_sources/mysource.py (no leading underscore)
# and it is picked up automatically (check: python3 manga.py sources).
#
# manga dict : id, title, desc, cover (url or file://), kind (MANGA/MANHWA/MANHUA), status,
#              year, tags[], authors[], official
# chapter    : id, num, vol, title, pages
# pages()    : list of image URLs or file:// paths, in reading order
# Ids you return are raw; the backend adds the "<ID>:" prefix.

class Source:
    ID = "mysrc"
    NAME = "My source"

    def browse(self, kind, sort, offset):
        return []

    def search(self, kind, q):
        return []

    def info(self, sid):
        raise NotImplementedError

    def chapters(self, sid):
        return []

    def pages(self, cid, saver=False):
        return []
