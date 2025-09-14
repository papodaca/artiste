require "spec_helper"

RSpec.describe HelpCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) { {"data" => {"post" => {"id" => "post-id", "channel_id" => "channel-id"}}} }
  let(:user_settings) { {theme: "dark"} }

  describe "#execute" do
    context "when command is executed" do
      let(:parsed_result) { {type: :help} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow(mattermost).to receive(:respond)
      end

      it "responds with the default help text" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response.length).to satisfy("Greater than zero") { |n| n > 0 }
        end

        command.execute
      end
    end
  end
end
