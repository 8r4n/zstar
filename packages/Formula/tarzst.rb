class Tarzst < Formula
  desc "A professional utility for creating secure, verifiable, and automated tar archives"
  homepage "https://github.com/8r4n/zstar"
  url "https://github.com/8r4n/zstar/archive/refs/tags/v3.1.tar.gz"
  version "3.1"
  license "MIT"

  depends_on "bash"
  depends_on "zstd"
  depends_on "gnupg"
  depends_on "coreutils"
  depends_on "pv" => :recommended

  def install
    bin.install "tarzst-project/tarzst.sh" => "tarzst"
    bin.install_symlink "tarzst" => "zstar"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/tarzst --help 2>&1", 0)
  end
end
