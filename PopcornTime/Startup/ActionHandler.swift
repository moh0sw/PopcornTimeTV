

import TVMLKitchen
import PopcornKit
import PopcornTorrent
import AVKit
import XCDYouTubeKit
import ObjectMapper

/**
 Handles all the navigation throughout the app. A string containing a method name and two optional parameters are passed into the `primary:` method. This in turn, generates the method from the string and executes it. Every method in this file has no public parameter names. This is for ease of use when calculating their names using perform selector.
 */
class ActionHandler: NSObject {
    
    /// Creates new instance of ActionHandler class
    static let shared = ActionHandler()
    
    /**
     Generate a method from a function signature and parameters.
     
     - Parameter named:         The valid name of a method inside the `ActionHandler` class.
     - Parameter parameters:    If the method has parameters, pass them in. 
     
     - Important: No more than 2 parameters may be passed in or application will crash.
     */
    private func performSelector(named methodSignature: String, parameters: [String]) {
        assert(parameters.count <= 2, "performSelector will not work with more than two function arguments.")
        
        switch parameters.count {
        case 0:
            let selector = Selector(methodSignature)
            perform(selector)
        case 1:
            let selector = Selector(methodSignature + ":")
            perform(selector, with: parameters[0])
        case 2:
            let selector = Selector(methodSignature + "::")
            perform(selector, with: parameters[0], with: parameters[1])
        default:
            return
        }
    }

    /**
     The action handler for when the primary (select) button is pressed

     - Parameter id: The actionID of the element pressed
     */
    func primary(_ id: String) {
        var pieces = id.components(separatedBy: "»")
        performSelector(named: pieces.removeFirst(), parameters: pieces)
    }
    
    /**
     The action handler for when the play button is pressed
     
     - Parameter id: The actionID of the element pressed
     */
    func play(_ id: String) {
        
    }
    
    /**
     Loads welcome view controller (App's first view controller).
     
     - Parameter completion: Optional completion handler called when view controller has loaded with a boolean value indicating success.
     */
    func showWelcome(completion: (((Bool) -> Void))? = nil) {
        let recipe = WelcomeRecipe(title: "PopcornTime")
        Kitchen.appController.evaluate(inJavaScriptContext: { (context) in
            
            let updateImage: @convention(block) (String, JSValue) -> Void = { (url, callback) in
                callback.call(withArguments: ["<img src=\"\(url)\" />"])
            }
            
            context.setObject(unsafeBitCast(updateImage, to: AnyObject.self),
                              forKeyedSubscript: "updateImage" as (NSCopying & NSObjectProtocol)!)
            
            if let file = Bundle.main.url(forResource: "WelcomeRecipe", withExtension: "js") {
                do {
                    let js = try String(contentsOf: file).replacingOccurrences(of: "{{RECIPE}}", with: recipe.xmlString)
                    context.evaluateScript(js)
                } catch {
                    print("Could not open ProductRecipe.js")
                }
            }
        }, completion: completion)
    }
    
    // MARK: - Watchlist
    
    /**
     Adds movie to the users watchlist if it's not added, removes if it is and optionally syncs with trakt. UI is updated here.
     
     - Parameter movieString: A JSON representation of the movie object to be added to the watchlist. Use `Mapper` to achieve this.
     */
    func toggleMovieWatchlist(_ movieString: String) {
        guard let movie = Mapper<Movie>().map(JSONString: movieString) else { return }
        WatchlistManager<Movie>.movie.isAdded(movie) ? WatchlistManager<Movie>.movie.remove(movie) : WatchlistManager<Movie>.movie.add(movie)
        Kitchen.appController.evaluate(inJavaScriptContext: { (context) in
            context.objectForKeyedSubscript("updateWatchlistButton").call(withArguments: [])
            }, completion: nil)
    }
    
    /**
     Adds show to the users watchlist if it's not added, removes if it is and optionally syncs with trakt. UI is updated here.
     
     - Parameter showString: A JSON representation of the show object to be added to the watchlist. Use `Mapper` to achieve this.
     */
    func toggleShowWatchlist(_ showString: String) {
        guard let show = Mapper<Show>().map(JSONString: showString) else { return }
        WatchlistManager<Show>.show.isAdded(show) ? WatchlistManager<Show>.show.remove(show) : WatchlistManager<Show>.show.add(show)
        Kitchen.appController.evaluate(inJavaScriptContext: { (context) in
            context.objectForKeyedSubscript("updateWatchlistButton").call(withArguments: [])
            }, completion: nil)
    }
    
    // MARK: - Watchedlist
    
    /**
     Marks a movie as watched and adds to the users watchedlist if it's not added, removes if it is and optionally syncs with trakt. UI is updated here.
     
     - Parameter movieString: A JSON representation of the movie object to be added to the watchedlist. Use `Mapper` to achieve this.
     */
    func toggleMovieWatchedlist(_ movieString: String) {
        guard let movie = Mapper<Movie>().map(JSONString: movieString) else { return }
        WatchedlistManager.movie.isAdded(movie.id) ? WatchedlistManager.movie.remove(movie.id) : WatchedlistManager.movie.add(movie.id)
        Kitchen.appController.evaluate(inJavaScriptContext: { (context) in
            context.objectForKeyedSubscript("updateWatchedlistButton").call(withArguments: [])
        }, completion: nil)
    }
    
    /**
     If the description exceeds 6 lines, it becomes selectable and calls this upon selection. 
     
     - Parameter title:     The title of the media the user is viewing.
     - Parameter message:   The full description.
     */
    func showDescription(_ title: String, _ message: String) {
        Kitchen.serve(recipe: DescriptionRecipe(title: title, message: message))
    }
    
    /// Dismisses the top modally presented view controller.
    func closeAlert() {
        Kitchen.dismissModal()
    }
    
    // MARK: - Movies
    
    
    /// Initialises and presents tabBarController with tabs: **Trending**, **Popular**, **Latest**, **Genre**, **Watchlist** and **Search** of type movies.
    func showMovies() {
        Kitchen.serve(recipe: KitchenTabBar(items: [Trending(.movies), Popular(.movies), Latest(.movies), Genre(.movies), Watchlist(.movies), Search(.movies)]))
    }
    
    /**
     Presents detail movie view. Called when a user taps on a movie.
     
     - Parameter title: The title of the movie.
     - Parameter id:    The imdbId of the movie.
     */
    func showMovie(_ title: String, _ id: String) {
        Kitchen.serve(recipe: LoadingRecipe(message: title))
        
        PopcornKit.getMovieInfo(id, tmdbId: nil) { (movie, error) in
            guard var movie = movie else {
                var viewcontrollers = Kitchen.navigationController.viewControllers
                viewcontrollers.removeLast()
                Kitchen.navigationController.setViewControllers(viewcontrollers, animated: true)
                Kitchen.serve(recipe: AlertRecipe(title: "Failed to load movie.", description: error?.code == 4 ? "No torrents available for selected movie." : error!.localizedDescription, buttons: [AlertButton(title: "Okay", actionID: "closeAlert")]))
                return
            }
            
            let group = DispatchGroup()
            
            group.enter()
            TraktManager.shared.getRelated(movie, completion: { (movies, _) in
                movie.related = movies
                group.leave()
            })
            
            group.enter()
            TraktManager.shared.getPeople(forMediaOfType: .movies, id: id, completion: { (actors, crew, _) in
                movie.actors = actors
                movie.crew = crew
                group.leave()
            })
            
            group.notify(queue: .main, execute: {
                let recipe =  MovieProductRecipe(movie: movie)
                Kitchen.appController.evaluate(inJavaScriptContext: { (context) in
                    
                    let disableThemeSong: @convention(block) (String) -> Void = { message in
                        ThemeSongManager.shared.stopTheme()
                    }
                    
                    let enableThemeSong: @convention(block) (String) -> Void = { message in
                        ThemeSongManager.shared.playMovieTheme(movie.title)
                    }
                    
                    context.setObject(unsafeBitCast(enableThemeSong, to: AnyObject.self),
                                      forKeyedSubscript: "enableThemeSong" as (NSCopying & NSObjectProtocol)!)
                    
                    context.setObject(unsafeBitCast(disableThemeSong, to: AnyObject.self),
                                      forKeyedSubscript: "disableThemeSong" as (NSCopying & NSObjectProtocol)!)
                    
                    if let file = Bundle.main.url(forResource: "ProductRecipe", withExtension: "js") {
                        do {
                            let js = try String(contentsOf: file).replacingOccurrences(of: "{{RECIPE}}", with: recipe.xmlString)
                            context.evaluateScript(js)
                        } catch {
                            print("Could not open ProductRecipe.js")
                        }
                    }
                    }, completion: nil)
                self.dismissLoading()
            })
        }
    }
    
    /// Pops the second last view controller from the navigation stack 1 second after the method is called. This can be used to dismiss the loading view controller that is presented when showing movie detail or show detail.
    func dismissLoading() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: {
            var viewcontrollers = Kitchen.navigationController.viewControllers
            viewcontrollers.remove(at: viewcontrollers.count-2)
            Kitchen.navigationController.setViewControllers(viewcontrollers, animated: false)
        })
    }
    
    // MARK: - Shows
    
    /// Initialises and presents tabBarController with tabs: **Trending**, **Popular**, **Latest**, **Genre**, **Watchlist** and **Search** of type shows.
    func showShows() {
        Kitchen.serve(recipe: KitchenTabBar(items: [Trending(.shows), Popular(.shows), Latest(.shows), Genre(.shows), Watchlist(.shows), Search(.shows)]))
    }
    
    /**
     Presents detail show view. Called when a user taps on a show.
     
     - Parameter title: The title of the show.
     - Parameter id:    The imdbId of the show.
     */
    func showShow(_ title: String, _ id: String) {
        Kitchen.serve(recipe: LoadingRecipe(message: title))
        
        PopcornKit.getShowInfo(id, tmdbId: nil) { (show, error) in
            guard var show = show else { return }
            
            let group = DispatchGroup()
            
            group.enter()
            TraktManager.shared.getRelated(show, completion: { (shows, _) in
                show.related = shows
                group.leave()
            })
            
            group.enter()
            TraktManager.shared.getPeople(forMediaOfType: .shows, id: id, completion: { (actors, crew, _) in
                show.actors = actors
                show.crew = crew
                group.leave()
            })
            
            group.enter()
            self.loadEpisodeMetadata(forShow: show) { episodes in
                show.episodes = episodes
                group.leave()
            }
            
            group.notify(queue: .main, execute: {
                var recipe = SeasonProductRecipe(show: show)
                Kitchen.appController.evaluate(inJavaScriptContext: { (context) in
                    let disableThemeSong: @convention(block) (String) -> Void = { message in
                        ThemeSongManager.shared.stopTheme()
                    }
                    
                    let enableThemeSong: @convention(block) (String) -> Void = { message in
                        if let id = show.tvdbId {
                            ThemeSongManager.shared.playShowTheme(Int(id)!)
                        }
                    }
                    
                    let updateSeason: @convention(block) (Int, JSValue) -> Void = { (number, callback) in
                        recipe.season = number
                        callback.call(withArguments: [recipe.template])
                    }
                    
                    context.setObject(unsafeBitCast(enableThemeSong, to: AnyObject.self),
                                      forKeyedSubscript: "enableThemeSong" as (NSCopying & NSObjectProtocol)!)
                    
                    context.setObject(unsafeBitCast(updateSeason, to: AnyObject.self),
                                      forKeyedSubscript: "updateSeason" as (NSCopying & NSObjectProtocol)!)
                    
                    context.setObject(unsafeBitCast(disableThemeSong, to: AnyObject.self),
                                      forKeyedSubscript: "disableThemeSong" as (NSCopying & NSObjectProtocol)!)
                    
                    if let file = Bundle.main.url(forResource: "ProductRecipe", withExtension: "js") {
                        do {
                            let js = try String(contentsOf: file).replacingOccurrences(of: "{{RECIPE}}", with: recipe.xmlString)
                            context.evaluateScript(js)
                        } catch {
                            print("Could not open ProductRecipe.js")
                        }
                    }
                }, completion: nil)
                self.dismissLoading()
            })
        }
    }
    
    /**
     Presents UI for user to choose a season to watch.
     
     Parameter showString: A JSON representation of the show object to be updated. Use `Mapper` to achieve this.
     Parameter episodesString: A JSON representation of the episode objects that metadata is to be fetched about. Use `Mapper` to achieve this.
     */
    func showSeasons(_ showString: String, _ episodesString: String) {
        guard var show = Mapper<Show>().map(JSONString: showString), let episodes = Mapper<Episode>().mapArray(JSONString: episodesString) else { return }
        show.episodes = episodes
        
        let group = DispatchGroup()
        var images = [String]()
        for season in show.seasonNumbers {
            group.enter()
            TMDBManager.shared.getSeasonPoster(ofShowWithImdbId: show.id, orTMDBId: show.tmdbId, season: season, completion: { (tmdb, image, error) in
                if let tmdb = tmdb { show.tmdbId = tmdb }
                images.append(image ?? show.largeCoverImage ?? "")
                group.leave()
            })
        }
        
        group.notify(queue: .main, execute: {
            let recipe = SeasonPickerRecipe(show: show, seasonImages: images)
            Kitchen.serve(recipe: recipe)
        })
    }
    
    /**
     Updates show detail UI with selected season information.
     
     Parameter number: String representation of the season to load.
     */
    func showSeason(_ number: String) {
        Kitchen.appController.evaluate(inJavaScriptContext: { (context) in
            context.objectForKeyedSubscript("changeSeason").call(withArguments: [Int(number)!])
            }, completion: nil)
    }
    
    /**
     Load episode images from trakt.
     
     - Parameter forShow:       The show that episode metadata is to be requested.
     - Parameter completion:    Completion handler containing the updated episodes.
     */
    func loadEpisodeMetadata(forShow show: Show, completion: @escaping ([Episode]) -> Void) {
        let group = DispatchGroup()
        
        var episodes = [Episode]()
        
        for var episode in show.episodes {
            group.enter()
            TMDBManager.shared.getEpisodeScreenshots(forShowWithImdbId: show.id, orTMDBId: show.tmdbId, season: episode.season, episode: episode.episode, completion: { (tmdbId, image, error) in
                if let image = image { episode.largeBackgroundImage = image }
                episodes.append(episode)
                group.leave()
            })
        }
        
        group.notify(queue: .main, execute: {
            episodes.sort(by: { $0.episode < $1.episode })
            completion(episodes)
        })
    }
    
    
    /// Presents the users watchlist for movies and shows.
    func showGlobalWatchlist() {
        Kitchen.serve(recipe: LoadingRecipe(message:"Loading..."))
        
        var recipe = WatchlistRecipe(title: "Watchlist")
        
        recipe.movies = WatchlistManager<Movie>.movie.getWatchlist { (movies) in
            recipe.movies = movies
        }
        
        recipe.shows = WatchlistManager<Show>.show.getWatchlist { (shows) in
            recipe.shows = shows
        }
        Kitchen.serve(recipe: recipe)
        dismissLoading()
    }

    /// Presents the settings view controller.
    func showSettings() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let viewController = storyboard.instantiateViewController(withIdentifier: "SettingsViewController") as? SettingsViewController {
            OperationQueue.main.addOperation({ 
                Kitchen.appController.navigationController.pushViewController(viewController, animated: true)
            })
        }
    }

    /**
     Presents a recipe with pages of information (catalog).
     
     - Parameter recipe:        The recipe to be presented.
     - Parameter topBarHidden:  Boolean value indicating if the tab bar controller is to be hidden when the view controller is pushed to the navigation stack. This must be set to true when presenting detail view controllers.
     */
    func serveCatalogRecipe(_ recipe: CatalogRecipe, topBarHidden hidden: Bool = false) {
        Kitchen.appController.evaluate(inJavaScriptContext: { jsContext in
            let highlightLockup: @convention(block) (JSValue) -> () = {(callback) in
                if callback.isObject {
                    recipe.lockup(didChangePage: { (lockUp) in
                        callback.call(withArguments: [lockUp])
                    })
                }
            }
            jsContext.setObject(unsafeBitCast(highlightLockup, to: AnyObject.self), forKeyedSubscript: "highlightLockup" as (NSCopying & NSObjectProtocol)!)

            if let file = Bundle.main.url(forResource: "Pagination", withExtension: "js") {
                do {
                    var js = try String(contentsOf: file).replacingOccurrences(of: "{{RECIPE}}", with: recipe.xmlString)
                    if hidden { js = js.replacingOccurrences(of: "{{TYPE}}", with: "catalog") }
                    jsContext.evaluateScript(js)
                } catch {
                    print("Could not open Pagination.js")
                }
            }

            }, completion: nil)
    }
    
    // MARK: - Genres
    
    /**
     Present a catalog of movies matching the passed in genre.
     
     - Parameter genre: The genre of the movies to be displayed.
     */
    func showMovieGenre(_ genre: String) {
        guard let genre = MovieManager.Genres(rawValue: genre) else { return }
        Kitchen.serve(recipe: LoadingRecipe(message: genre.rawValue))
        
        var recipe: CatalogRecipe!
        recipe = CatalogRecipe(title: genre.rawValue, fetchBlock: { (page, completion) in
            PopcornKit.loadMovies(page, genre: genre, completion: { (movies, error) in
                guard let movies = movies else { return }
                completion(movies.map({$0.lockUp}).joined(separator: ""))
                self.serveCatalogRecipe(recipe, topBarHidden: true)
                self.dismissLoading()
            })
        })
    }
    
    /**
     Present a catalog of shows matching the passed in genre.
     
     - Parameter genre: The genre of the shows to be displayed.
     */
    func showShowGenre(_ genre: String) {
        guard let genre = ShowManager.Genres(rawValue: genre) else { return }
        Kitchen.serve(recipe: LoadingRecipe(message: genre.rawValue))
        
        var recipe: CatalogRecipe!
        recipe = CatalogRecipe(title: genre.rawValue, fetchBlock: { (page, completion) in
            PopcornKit.loadShows(page, genre: genre, completion: { (shows, error) in
                guard let shows = shows else {  return }
                completion(shows.map({$0.lockUp}).joined(separator: ""))
                self.serveCatalogRecipe(recipe, topBarHidden: true)
                self.dismissLoading()
            })
        })
    }

    
    // MARK: - Credits
    
    /**
     Present a catalog of movies that an actor starred in or was working in.
     
     - Parameter name:  Name of person.
     - Parameter id:    ImdbId of person.
     */
    func showMovieCredits(_ name: String, _ id: String) {
        Kitchen.serve(recipe: LoadingRecipe(message: name))
        
        var recipe: CatalogRecipe!
        recipe = CatalogRecipe(title: name, fetchBlock: { (page, completion) in
            TraktManager.shared.getMediaCredits(forPersonWithId: id, mediaType: Movie.self) { (movies, error) in
                guard !movies.isEmpty else { return }
                completion(movies.map({$0.lockUp}).joined(separator: ""))
                self.serveCatalogRecipe(recipe, topBarHidden: true)
                self.dismissLoading()
            }
        })
    }
    
    /**
     Present a catalog of shows that an actor starred in or was working in.
     
     - Parameter name:  Name of person.
     - Parameter id:    ImdbId of person.
     */
    func showShowCredits(_ name: String, _ id: String) {
        Kitchen.serve(recipe: LoadingRecipe(message: name))
        
        var recipe: CatalogRecipe!
        recipe = CatalogRecipe(title: name, fetchBlock: { (page, completion) in
            TraktManager.shared.getMediaCredits(forPersonWithId: id, mediaType: Show.self) { (shows, error) in
                guard !shows.isEmpty else { return }
                completion(shows.map({$0.lockUp}).joined(separator: ""))
                self.serveCatalogRecipe(recipe, topBarHidden: true)
                self.dismissLoading()
            }
        })
    }
    
    // MARK: - Media
    
    /**
     Begin streaming a movie. This method will handle presenting the loading view controller as well as the playing view controller.
     
     - Parameter torrentString: A JSON representation of the torrent object to be streamed. Use `Mapper` to achieve this.
     - Parameter mediaString:   A JSON representation of the movie or show object to be streamed. Use `Mapper` to achieve this.
     */
    func streamTorrent(_ torrentString: String, _ mediaString: String) {
        guard var media: Media = Mapper<Movie>().map(JSONString: mediaString) ?? Mapper<Episode>().map(JSONString: mediaString),
                let torrent = Mapper<Torrent>().map(JSONString: torrentString) else { return }
        
        Kitchen.dismissModal()
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        
        let present: (UIViewController, Bool) -> Void = { (viewController, animated) in
            OperationQueue.main.addOperation({
                Kitchen.appController.navigationController.pushViewController(viewController, animated: animated)
            })
        }
        
        let currentProgress = media is Movie ? WatchedlistManager.movie.currentProgress(media.id) : WatchedlistManager.episode.currentProgress(media.id)
        
        let loadingViewController = storyboard.instantiateViewController(withIdentifier: "LoadingViewController") as! LoadingViewController
        loadingViewController.backgroundImageString = media.largeBackgroundImage
        loadingViewController.mediaTitle = media.title
        present(loadingViewController, true)
        
        let error: (String) -> Void = { (errorMessage) in
            Kitchen.serve(recipe: AlertRecipe(title: "Error", description: errorMessage, buttons: [AlertButton(title: "Okay", actionID: "closeAlert")]))
        }
        
        let finishedLoading: (LoadingViewController, UIViewController) -> Void = { (loadingVc, playerVc) in
            OperationQueue.main.addOperation {
                Kitchen.appController.navigationController.popViewController(animated: true)
            }
            present(playerVc, true)
        }
        
        let playViewController = storyboard.instantiateViewController(withIdentifier: "PCTPlayerViewController") as! PCTPlayerViewController
        
        
        getSubtitles(forMedia: media, id: media.id) { subtitles in
            media.subtitles = subtitles
            media.play(fromFileOrMagnetLink: torrent.magnet ?? torrent.url, loadingViewController: loadingViewController, playViewController: playViewController, progress: currentProgress, errorBlock: error, finishedLoadingBlock: finishedLoading)
        }
    }
    
    /**
     Retrieves subtitles from OpenSubtitles
     
     - Parameter media: The media to fetch subtitles for.
     - Parameter id:    The imdbId of the movie. If the media is an episode, an imdbId will be fetched automatically.
     
     - Parameter completion: The completion handler for the request containing an array of subtitles
     */
    func getSubtitles(forMedia media: Media, id: String, completion: @escaping ([Subtitle]) -> Void) {
        if let episode = media as? Episode, !id.hasPrefix("tt") {
            TraktManager.shared.getEpisodeMetadata(episode.show.id, episodeNumber: episode.episode, seasonNumber: episode.season, completion: { [weak self] (tvdb, imdb, error) in
                if let imdb = imdb { self?.getSubtitles(forMedia: media, id: imdb, completion: completion) } else {
                    completion([Subtitle]())
                }
            })
        } else {
            SubtitlesManager.shared.search(imdbId: id) { (subtitles, _) in
                completion(subtitles)
            }
        }
    }

    /**
     Watch a movies trailer. Handles presenting play view controller and errors thrown by XCDYouTubeKit.
     
     - Parameter code: The 11 digit YouTube identifier of the trailer.
     */
    func playTrailer(_ code: String) {
        let playerController = AVPlayerViewController()
        Kitchen.appController.navigationController.pushViewController(playerController, animated: true)
        XCDYouTubeClient.default().getVideoWithIdentifier(code) { (video, error) in
            guard let streamUrls = video?.streamURLs,
            let qualities = Array(streamUrls.keys) as? [UInt] else { return }
            let preferredVideoQualities = [XCDYouTubeVideoQuality.HD720.rawValue, XCDYouTubeVideoQuality.medium360.rawValue, XCDYouTubeVideoQuality.small240.rawValue]
            var videoUrl: URL?
            forLoop: for quality in preferredVideoQualities {
                if let index = qualities.index(of: quality) {
                    videoUrl = Array(streamUrls.values)[index]
                    break forLoop
                }
            }
            guard let url = videoUrl else {
                Kitchen.appController.navigationController.popViewController(animated: true)
                Kitchen.serve(recipe: AlertRecipe(title: "Oops!", description: "Error fetching valid trailer URL from Youtube.", buttons: [AlertButton(title: "Okay", actionID: "closeAlert")]))
                return
            }
            
            ThemeSongManager.shared.stopTheme()
            
            playerController.player = AVPlayer(url: url)
            playerController.player!.play()
            
            NotificationCenter.default.addObserver(self, selector: #selector(self.playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        }
    }
    
    /// Called when AVPlayerViewController stops playing
    func playerDidFinishPlaying() {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        OperationQueue.main.addOperation {
            Kitchen.appController.navigationController.popViewController(animated: true)
        }
    }
    
    /**
     Presents UI for picking torrent quality.
     
     - Parameter torrentsString:    A JSON representation of the torrent objects. Use `Mapper` to achieve this.
     - Parameter mediaString:       A JSON representation of the movie or show object. Use `Mapper` to achieve this.
     */
    func chooseQuality(_ torrentsString: String, _ mediaString: String) {
        guard let torrents = Mapper<Torrent>().mapArray(JSONString: torrentsString) else {
            Kitchen.serve(recipe: AlertRecipe(title: "No torrents found", description: "Torrents could not be found for the specified movie.", buttons: [AlertButton(title: "Okay", actionID: "closeAlert")]))
            return
        }
        let buttons = torrents.map({ AlertButton(title: $0.quality, actionID: "streamTorrent»\(Mapper<Torrent>().toJSONString($0)?.cleaned ?? "")»\(mediaString.cleaned)") })
        
        Kitchen.serve(recipe: AlertRecipe(title: "Choose Quality", description: "Choose a quality to stream.", buttons: buttons))
    }
}
