using Gee;

namespace XSRSS
{
	public class WebInterface : Object
	{
		private Soup.Server server;

		public WebInterface()
		{
			server = new Soup.Server("port",9889);
			server.add_handler("/",list_all_items);
			server.add_handler("/feeds",list_feeds);
			server.add_handler("/static",static_files);
			server.add_handler("/feed",show_feed);
			server.add_handler("/markasread",mark_item_as_read);
			server.run_async();
		}

		private void static_files(Soup.Server server,Soup.Message msg,string? path,HashTable<string,string>? query,Soup.ClientContext client)
		{
			// We should probably sanitize the path here to make sure it
			// doesn't go anywhere above static/
			string filename = path.substring(1);
			if(FileUtils.test(filename,FileTest.EXISTS))
			{
				// This probably only handles smallish files that can be read
				// fully into memory
				try
				{
					uint8[] file_data;
					if(FileUtils.get_data(filename,out file_data))
					{
						bool result_uncertain;
						string mime_type = ContentType.guess(filename,file_data,out result_uncertain);
						stdout.printf("mime-type: %s%s\n",mime_type,result_uncertain ? ", guessed" : "");
						msg.set_status(Soup.KnownStatusCode.OK);
						msg.set_response(mime_type,Soup.MemoryUse.COPY,file_data);
					} else
					{
						stderr.printf("Could not read file %s\n",filename);
						msg.set_status(Soup.KnownStatusCode.NOT_FOUND);
						msg.set_response("text/html",Soup.MemoryUse.COPY,"File not found".data);
					}
				} catch(Error e)
				{
					stderr.printf("Error opening file %s\n",filename);
					msg.set_status(Soup.KnownStatusCode.NOT_FOUND);
					msg.set_response("text/html",Soup.MemoryUse.COPY,"File not found".data);
				}
			} else
			{
				msg.set_status(Soup.KnownStatusCode.NOT_FOUND);
				msg.set_response("text/html",Soup.MemoryUse.COPY,"File not found".data);
			}
		}

		private void mark_item_as_read(Soup.Server server,Soup.Message msg,string? path,HashTable<string,string>? query,Soup.ClientContext client)
		{
			string item_guid = Uri.unescape_string(path.substring(12)); // /markasread/
			stdout.printf("item_guid: \"%s\"\n",item_guid);
			bool found_item = false;
			foreach(Feed feed in Instance.feed_manager.feeds)
			{
				foreach(Feed.Item item in feed.items)
				{
					if(item.guid == item_guid)
					{
						item.read = true;
						feed.save_data_to_database();
						found_item = true;
						break;
					}
				}
				if(found_item)
				{
					break;
				}
			}
			msg.set_status(Soup.KnownStatusCode.OK);
			if(found_item)
			{
				msg.set_response("text/html",Soup.MemoryUse.COPY,"Item marked as read successfully.".data);
			} else
			{
				msg.set_response("text/html",Soup.MemoryUse.COPY,"Item not found!".data);
			}
		}

		private void list_all_items(Soup.Server server,Soup.Message msg,string? path,HashTable<string,string>? query,Soup.ClientContext client)
		{
			LinkedList<Feed.Item> items = assemble_item_list(null);
			Template template = new Template("feed");
			if(items != null)
			{
				LinkedList<HashMap<string,string>> items_list = new LinkedList<HashMap<string,string>>();
				foreach(Feed.Item item in items)
				{
					HashMap<string,string> variables = new HashMap<string,string>();
					variables["title"] = item.title;
					variables["unread"] = item.read ? "" : " unread";
					variables["markasread"] = item.read ? "" : " - <a href=\"/markasread/%s\">Mark as read</a>".printf(Uri.escape_string(item.guid));
					variables["pubdate"] = item.pub_date != null ? item.pub_date.format("%F %T") : "";
					variables["link"] = item.link != null ? "<a href=\"%s\">".printf(item.link) : "";
					variables["endlink"] = item.link != null ? "</a>" : "";
					variables["text"] = item.content != null ? item.content : (item.description != null ? item.description : "");
					items_list.add(variables);
				}
				template.define_foreach("item",items_list);
			}
			template.define_variable("title","All items");
			template.define_variable("feed","Showing all items");
			if(items == null)
			{
				template.define_variable("noitems","<span class=\"noitems\">There are no items in the database.</span>");
			}
			msg.set_status(Soup.KnownStatusCode.OK);
			msg.set_response("text/html",Soup.MemoryUse.COPY,template.render().data);
		}

		private void list_feeds(Soup.Server server,Soup.Message msg,string? path,HashTable<string,string>? query,Soup.ClientContext client)
		{
			Template template = new Template("list_feeds");
			template.define_variable("title","All feeds");
			template.define_variable("numfeeds",Instance.feed_manager.feeds.size.to_string());
			StringBuilder feed_list = new StringBuilder();
			foreach(Feed feed in Instance.feed_manager.feeds)
			{
				feed_list.append("<li><a href=\"/feed/%s\">%s</a></li>\n".printf(feed.user_name,feed.user_name));
			}
			template.define_variable("feeds",feed_list.str);
			msg.set_status(Soup.KnownStatusCode.OK);
			msg.set_response("text/html",Soup.MemoryUse.COPY,template.render().data);
		}

		private void show_feed(Soup.Server server,Soup.Message msg,string? path,HashTable<string,string>? query,Soup.ClientContext client)
		{
			string feed_name = path.substring(6);
			LinkedList<Feed.Item> items = assemble_item_list(feed_name);
			Template template = new Template("feed");
			if(items != null)
			{
				LinkedList<HashMap<string,string>> items_list = new LinkedList<HashMap<string,string>>();
				foreach(Feed.Item item in items)
				{
					HashMap<string,string> variables = new HashMap<string,string>();
					variables["title"] = item.title;
					variables["unread"] = item.read ? "" : " unread";
					variables["markasread"] = item.read ? "" : " - <a href=\"/markasread/%s\">Mark as read</a>".printf(item.guid);
					variables["pubdate"] = item.pub_date != null ? item.pub_date.format("%F %T") : "";
					variables["link"] = item.link != null ? "<a href=\"%s\">".printf(item.link) : "";
					variables["endlink"] = item.link != null ? "</a>" : "";
					variables["text"] = item.content != null ? item.content : (item.description != null ? item.description : "");
					items_list.add(variables);
				}
				template.define_foreach("item",items_list);
			}
			template.define_variable("title",feed_name);
			template.define_variable("feed",feed_name);
			if(items == null)
			{
				template.define_variable("noitems","<span class=\"noitems\">There are no items in this feed.</span>");
			}
			msg.set_status(Soup.KnownStatusCode.OK);
			msg.set_response("text/html",Soup.MemoryUse.COPY,template.render().data);
		}

		private LinkedList<Feed.Item>? assemble_item_list(string? feed_name)
		{
			LinkedList<Feed.Item> item_list = new LinkedList<Feed.Item>();
			if(feed_name == null)
			{
				// Assemble the list with all items from all feeds
				foreach(Feed feed in Instance.feed_manager.feeds)
				{
					foreach(Feed.Item item in feed.items)
					{
						item_list.add(item);
					}
				}
			} else
			{
				bool found_feed = false;
				foreach(Feed feed in Instance.feed_manager.feeds)
				{
					if(feed.user_name == feed_name)
					{
						found_feed = true;
						foreach(Feed.Item item in feed.items)
						{
							item_list.add(item);
						}
						break;
					}
				}
				if(!found_feed)
				{
					return null;
				}
			}
			item_list.sort((CompareDataFunc<Feed.Item>)compare_item_by_reverse_pub_date);
			return item_list;
		}

		private static int compare_item_by_reverse_pub_date(Feed.Item a,Feed.Item b)
		{
			return -a.pub_date.compare(b.pub_date);
		}

	}
}
