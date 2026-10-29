import Testing
@testable import DogearKit

@Test(arguments: [
    ("https://gist.github.com/a/1", "github.com"), ("https://github.com/a", "github.com"),
    ("https://twitter.com/a/status/1", "x.com"), ("https://mobile.twitter.com/a", "x.com"), ("https://x.com/a", "x.com"),
    ("https://youtu.be/abc", "youtube.com"), ("https://m.youtube.com/watch?v=1", "youtube.com"),
    ("https://www.nytimes.com/2026/a", "nytimes.com"), ("https://WWW.Example.COM/a", "example.com"),
    ("https://open.spotify.com/track/1", "spotify.com"),
    ("https://www.bbc.co.uk/news", "bbc.co.uk"), ("https://news.example.com.au/a", "example.com.au"),
    ("http://192.168.1.1/admin", "192.168.1.1"), ("http://localhost:8080/", "localhost"),
    ("not a url", ""), ("https://", ""),
])
func aLinkGetsTheNameOfItsSite(url: String, site: String) {
    #expect(SiteLabel.of(url) == site)
}
