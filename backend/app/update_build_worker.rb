class UpdateBuildWorker
  include Sidekiq::Worker
  sidekiq_options :retry => false

  def perform(build_hash)
    build = ParseBuild.new build_hash
    updated_build = BuildFetcher.create(build).fetch
    merged_build = ParseBuild.merge(build, updated_build)

    client = ParseClient.from_settings
    client.notify_build_failed(merged_build) if changed_to_failed?(build, updated_build)

    if changed?(build, updated_build)
      client.update(merged_build)
      push_change(merged_build)
    end
  end

  private

  def changed_to_failed?(original, updated)
    !original.status.include?("failed") && updated.status.include?("failed")
  end

  def changed?(original, updated)
    original.status != updated.status ||
      original.branch != updated.branch ||
      original.isInvalid != updated.isInvalid ||
      original.commitSha != updated.commitSha ||
      original.finishedAtTime != updated.finishedAtTime
  end

  def push_change(build)
    pusher = PusherClient.from_settings
    pusher.push(build.user.objectId, build)
  end
end
