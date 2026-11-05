import Foundation

/// AniList's Media.airingSchedule does not accept a sort argument.
/// Latest released episodes belong to Page.airingSchedules, where TIME_DESC is supported.
enum MetadataQueries {
    static let fields = "id title{english romaji} coverImage{large extraLarge} bannerImage description episodes status averageScore genres seasonYear format nextAiringEpisode{episode airingAt}"
    static let home = "query($s:MediaSeason,$y:Int){trending:Page(page:1,perPage:25){media(type:ANIME,sort:TRENDING_DESC,status:RELEASING,isAdult:false){\(fields)}}seasonal:Page(page:1,perPage:24){media(type:ANIME,season:$s,seasonYear:$y,sort:POPULARITY_DESC,isAdult:false){\(fields)}}}"
    static let detail = "query($id:Int){Media(id:$id,type:ANIME){\(fields)} aired:Page(page:1,perPage:1){airingSchedules(mediaId:$id,notYetAired:false,sort:TIME_DESC){episode airingAt}}}"
    static let latestEpisodes = "query($now:Int){Page(page:1,perPage:20){airingSchedules(notYetAired:false,airingAt_lesser:$now,sort:TIME_DESC){episode airingAt media{id type isAdult title{english romaji} coverImage{large}}}}}"
}
