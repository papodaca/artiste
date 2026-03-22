require "spec_helper"

RSpec.describe "get_album_cover_path helper" do
  def get_album_cover_path(audio_path)
    return nil unless audio_path

    base_name = File.basename(audio_path, ".*")
    dir = File.dirname(audio_path)
    cover_relative_path = "#{dir}/cover_#{base_name}.png"
    cover_full_path = File.join("db", "music", cover_relative_path)

    File.exist?(cover_full_path) ? "/music/#{cover_relative_path}" : nil
  end

  before do
    allow(File).to receive(:exist?)
  end

  it "returns cover path when cover exists" do
    allow(File).to receive(:exist?).with("db/music/2024/01/01/cover_song.png").and_return(true)
    result = get_album_cover_path("2024/01/01/song.m4a")
    expect(result).to eq("/music/2024/01/01/cover_song.png")
  end

  it "returns nil when cover does not exist" do
    allow(File).to receive(:exist?).with("db/music/2024/01/01/cover_song.png").and_return(false)
    result = get_album_cover_path("2024/01/01/song.m4a")
    expect(result).to be_nil
  end

  it "returns nil when path is nil" do
    result = get_album_cover_path(nil)
    expect(result).to be_nil
  end
end
