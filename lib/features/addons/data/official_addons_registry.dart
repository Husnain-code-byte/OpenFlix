import '../domain/models/addon_models.dart';

/// Official CloudStream 3 repositories curated for OpenFlix.
/// None are installed automatically at startup — users explicitly opt in.
const List<OfficialCloudStreamRepoEntry> kOfficialCloudStreamRepos = [
  OfficialCloudStreamRepoEntry(
    id: 'cs_megix',
    name: 'Megix Repo',
    shortcode: 'megix',
    languageBadge: 'Hindi + English',
    description:
        'Hindi & English CloudStream repository (CineStream, Bollyflix, VegaMovies, UHDMovies, and multi-audio extractors).',
    repoUrl: 'https://raw.githubusercontent.com/SaurabhKaperwan/CSX/builds/CS.json',
    tags: ['Hindi + English', 'Movies & Series', '.cs3'],
  ),
  OfficialCloudStreamRepoEntry(
    id: 'cs_cnc',
    name: 'CNC Repo',
    shortcode: 'cncverse',
    languageBadge: 'All Language',
    description:
        'CNCVerse multi-language CloudStream repository spanning global cinema, OTT mirrors, anime, and international streams.',
    repoUrl:
        'https://raw.githubusercontent.com/NivinCNC/CNCVerse-Cloud-Stream-Extension/refs/heads/builds/CNC.json',
    tags: ['All Language', 'Global', '.cs3'],
  ),
  OfficialCloudStreamRepoEntry(
    id: 'cs_phisher',
    name: 'Phisher Repo',
    shortcode: 'phisher98',
    languageBadge: 'English + Multi',
    description:
        'Phisher98 community CloudStream repository featuring StreamPlay, HiAnime, SuperStream, and dozens of active scrapers.',
    repoUrl:
        'https://raw.githubusercontent.com/phisher98/cloudstream-extensions-phisher/refs/heads/builds/repo.json',
    tags: ['Multi-Provider', 'Anime & Movies', '.cs3'],
  ),
  OfficialCloudStreamRepoEntry(
    id: 'cs_cinephile',
    name: 'Cinephile',
    shortcode: 'cinephile',
    languageBadge: 'English + Regional',
    description:
        'Curated cinema & series CloudStream repository by rockhero1234 with direct 1080p/4K stream extractors.',
    repoUrl:
        'https://raw.githubusercontent.com/rockhero1234/cinephile/refs/heads/builds/repo.json',
    tags: ['Cinema', 'Series', '.cs3'],
  ),
  OfficialCloudStreamRepoEntry(
    id: 'cs_reflex',
    name: 'Reflex Repo',
    shortcode: 'reflex',
    languageBadge: 'English',
    description:
        'Reflex755 CloudStream repository with fast English movie and TV series resolvers.',
    repoUrl:
        'https://raw.githubusercontent.com/Reflex755/ReflexRepo/refs/heads/builds/repo.json',
    tags: ['English', 'Fast HLS', '.cs3'],
  ),
  OfficialCloudStreamRepoEntry(
    id: 'cs_raghav',
    name: 'Raghav Repo',
    shortcode: 'raghav',
    languageBadge: 'Hindi + Anime',
    description:
        'Raghav CloudStream extension repository featuring anime, dual-audio releases, and regional Indian sources.',
    repoUrl:
        'https://raw.githubusercontent.com/KSHITIJ8473/raghav/builds/repo.json',
    tags: ['Anime', 'Hindi + Regional', '.cs3'],
  ),
  OfficialCloudStreamRepoEntry(
    id: 'cs_allforu',
    name: 'AllForU',
    shortcode: 'allforu',
    languageBadge: 'Multi-Language',
    description:
        'AllForU CloudStream repository with multi-language movies, series, and regional providers.',
    repoUrl:
        'https://raw.githubusercontent.com/RVRBEAST76/allforu-repo/builds/repo.json',
    tags: ['Multi-Language', 'Movies & TV', '.cs3'],
  ),
  OfficialCloudStreamRepoEntry(
    id: 'cs_recloudstream',
    name: 'CloudStream Providers Repository',
    shortcode: 'recloudstream',
    languageBadge: 'Official Base',
    description:
        'Baseline recloudstream/extensions provider repository maintained alongside the core CloudStream runtime.',
    repoUrl:
        'https://raw.githubusercontent.com/recloudstream/extensions/master/repo.json',
    tags: ['Baseline', 'Core API', '.cs3'],
  ),
];

/// Official Stremio Addons directory slot.
/// Intentionally empty until official Stremio entries are finalized — custom
/// Stremio manifests & `/configure` deep links work immediately via the Add Addons bar.
const List<OfficialStremioAddonEntry> kOfficialStremioAddons = [];
