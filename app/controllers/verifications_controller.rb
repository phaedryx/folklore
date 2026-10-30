class VerificationsController < ApplicationController
  def create
    # Forward stale_after only when it was sent: Assets::Verify tells
    # "omitted" (leave the review date) from "empty" (clear it).
    args = { actor: current_actor, slug: params[:slug] }
    args[:stale_after] = params[:stale_after] if params.key?(:stale_after)

    Assets::Verify.mutate(**args)
    redirect_back fallback_location: stale_path, notice: "Verified."
  end

  private

  def error_fallback_location
    stale_path
  end
end
