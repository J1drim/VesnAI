import 'api_client.dart';

/// Polls a background job until it reaches a terminal state.
///
/// The search/enrich endpoints currently run to completion server-side and
/// return a finished job dict, so callers can often skip polling. This helper
/// covers any genuinely asynchronous job and is the client seam that an SSE
/// stream (`GET /v1/jobs/{id}/events`) can later replace.
class JobPoller {
  final VesnaiApiClient client;
  final Duration interval;

  JobPoller(this.client, {this.interval = const Duration(milliseconds: 400)});

  Future<Map<String, dynamic>> wait(
    String jobId, {
    void Function(double progress, String message)? onProgress,
  }) async {
    while (true) {
      final job = await client.getJob(jobId);
      onProgress?.call(
        (job['progress'] as num?)?.toDouble() ?? 0,
        (job['message'] as String?) ?? '',
      );
      final status = job['status'] as String?;
      if (status == 'succeeded' || status == 'failed') return job;
      await Future<void>.delayed(interval);
    }
  }
}
