//
//  CoreDataFeedStore.swift
//  FeedStoreChallenge
//
//  Created by Chad Chang on 2021/2/21.
//  Copyright © 2021 Essential Developer. All rights reserved.
//

import CoreData

public final class CoreDataFeedStore: FeedStore {
	private let container: NSPersistentContainer
	private let modelName = "FeedStore"
	private let backgroundContext: NSManagedObjectContext

	public init(modelURL: URL, bundle: Bundle = .main) throws {
		container = try NSPersistentContainer.load(modelName: modelName, url: modelURL, in: bundle)
		backgroundContext = container.newBackgroundContext()
	}

	public func deleteCachedFeed(completion: @escaping DeletionCompletion) {
		let context = self.backgroundContext
		context.perform {
			do {
				let request: NSFetchRequest<ManagedCache> = ManagedCache.fetchRequest()
				request.returnsObjectsAsFaults = false

				if let cache = try context.fetch(request).first {
					context.delete(cache)
					try context.save()
				}
				completion(nil)
			} catch {
				completion(error)
			}
		}
	}

	public func insert(_ feed: [LocalFeedImage], timestamp: Date, completion: @escaping InsertionCompletion) {
		let context = self.backgroundContext
		context.perform {
			do {
				let request: NSFetchRequest<ManagedCache> = ManagedCache.fetchRequest()
				request.returnsObjectsAsFaults = false

				if let cache = try context.fetch(request).first {
					context.delete(cache)
				}

				let managedCache = ManagedCache(context: context)
				managedCache.timestamp = timestamp
				managedCache.feed = NSOrderedSet(array: feed.map { local in
					let managed = ManagedFeedImage(context: context)
					managed.id = local.id
					managed.imageDescription = local.description
					managed.location = local.location
					managed.url = local.url
					return managed
				})

				try context.save()
				completion(nil)
			} catch {
				completion(error)
			}
		}
	}

	public func retrieve(completion: @escaping RetrievalCompletion) {
		let context = self.backgroundContext
		context.perform {
			do {
				let request: NSFetchRequest<ManagedCache> = ManagedCache.fetchRequest()
				request.returnsObjectsAsFaults = false
				
				if let cache = try context.fetch(request).first {
					completion(.found(
								feed: cache.feed
									.compactMap { ($0 as? ManagedFeedImage) }
									.map {
										LocalFeedImage(id: $0.id, description: $0.imageDescription, location: $0.location, url: $0.url)
									},
								timestamp: cache.timestamp))
				} else {
					completion(.empty)
				}
			} catch {
				completion(.failure(error))
			}
		}
	}
}

private extension NSPersistentContainer {
	enum LoadingError: Swift.Error {
		case modelNotFound
		case failedToLoadPersistentStores(Swift.Error)
	}
	static func load(modelName name: String, url: URL, in bundle: Bundle) throws -> NSPersistentContainer {
		guard let model = NSManagedObjectModel.with(name: name, in: bundle) else {
			throw LoadingError.modelNotFound
		}

		let description = NSPersistentStoreDescription(url: url)
		let container = NSPersistentContainer(name: name, managedObjectModel: model)
		container.persistentStoreDescriptions = [description]

		var loadError: Swift.Error?
		container.loadPersistentStores { loadError = $1 }
		try loadError.map { throw LoadingError.failedToLoadPersistentStores($0) }

		return container
	}
}

private extension NSManagedObjectModel {
	static func with(name: String, in bundle: Bundle) -> NSManagedObjectModel? {
		return bundle
			.url(forResource: name, withExtension: "momd")
			.flatMap { NSManagedObjectModel(contentsOf: $0) }
	}
}

@objc(ManagedCache)
private class ManagedCache: NSManagedObject {
	private static let entityName = String(describing: ManagedCache.self)

	@NSManaged var timestamp: Date
	@NSManaged var feed: NSOrderedSet

	fileprivate class func fetchRequest() -> NSFetchRequest<ManagedCache> {
		return NSFetchRequest<ManagedCache>(entityName: entityName)
	}
}

@objc(ManagedFeedImage)
private class ManagedFeedImage: NSManagedObject {
	@NSManaged var id: UUID
	@NSManaged var imageDescription: String?
	@NSManaged var location: String?
	@NSManaged var url: URL
	@NSManaged var cache: ManagedCache
}
