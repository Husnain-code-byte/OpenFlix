/// External community and GitHub release endpoints for OpenFlix.
abstract final class AppLinks {
  static const String githubOwner = 'Husnain-code-byte';
  static const String githubRepo = 'OpenFlix';
  static const String discordInviteUrl = 'https://discord.gg/y5QssSBcpJ';
  static const String releasesApiUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';
  static const String releasesHtmlFallbackUrl =
      'https://github.com/$githubOwner/$githubRepo/releases/latest';
}
