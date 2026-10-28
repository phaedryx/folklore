require "test_helper"

class Layout::FlashComponentTest < ViewComponent::TestCase
  test "renders notice and alert with their test ids" do
    render_inline Layout::FlashComponent.new(flash: { "notice" => "Saved.", "alert" => "Nope." })

    assert_selector "[data-testid='flash-notice']", text: "Saved."
    assert_selector "[data-testid='flash-alert'][role='alert']", text: "Nope."
  end

  test "renders nothing for an empty flash" do
    render_inline Layout::FlashComponent.new(flash: {})

    assert_no_selector "[data-testid^='flash']"
  end
end
