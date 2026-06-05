import React, { useState, useEffect, useRef } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Send, AlertCircle, Clock, Trash2, Calendar, Smile, ShieldCheck, CheckCheck, MessageSquare, Users, Search } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';

export const ChatScreen: React.FC = () => {
  const navigate = useNavigate();
  const { userId } = useParams<{ userId: string }>(); // otherUserId
  const { currentUser } = useAuth();
  
  const [messages, setMessages] = useState<any[]>([]);
  const [otherUser, setOtherUser] = useState<any | null>(null);
  const [isOtherOnline, setIsOtherOnline] = useState(false);
  const [inputVal, setInputVal] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  
  // Left-pane thread and contact list states
  const [activeTab, setActiveTab] = useState<'chats' | 'contacts'>('chats');
  const [chats, setChats] = useState<any[]>([]);
  const [contacts, setContacts] = useState<any[]>([]);
  const [searchQuery, setSearchQuery] = useState('');

  // Event mentions state
  const [allEvents, setAllEvents] = useState<any[]>([]);
  const [showEventDropdown, setShowEventDropdown] = useState(false);
  const [filteredEvents, setFilteredEvents] = useState<any[]>([]);
  const [mentionQuery, setMentionQuery] = useState('');

  const scrollRef = useRef<HTMLDivElement | null>(null);

  const generateConvId = (id1: string, id2: string) => {
    const ids = [id1, id2];
    ids.sort();
    return ids.join('_');
  };

  const loadLeftPaneData = async () => {
    if (!currentUser) return;
    try {
      // 1. Fetch conversations from recent_chats view
      const { data: recentData } = await supabase
        .from('recent_chats')
        .select()
        .or(`sender_id.eq.${currentUser.id},receiver_id.eq.${currentUser.id}`)
        .order('last_message_time', { ascending: false });

      // 2. Fetch contacts (all users except current user)
      const { data: usersData } = await supabase
        .from('users')
        .select('id, name, role, post, email')
        .neq('id', currentUser.id)
        .order('name');

      const loadedContacts = usersData || [];
      setContacts(loadedContacts);

      // Map recent chats and filter for direct chats
      const allRecent = (recentData || []).map((c: any) => {
        const otherUserId = c.sender_id === currentUser.id ? c.receiver_id : c.sender_id;
        const otherUser = loadedContacts.find((u: any) => u.id === otherUserId) || {
          id: otherUserId,
          name: c.sender_name || 'Unknown',
          role: 'Member'
        };

        return {
          ...c,
          otherUserId,
          otherUser
        };
      });

      const dms = allRecent.filter((c: any) => !c.folder_id && c.otherUserId);
      setChats(dms);
    } catch (e) {
      console.error('Error loading left pane data:', e);
    }
  };

  const loadData = async () => {
    if (!currentUser || !userId) return;
    try {
      setIsLoading(true);
      // Load both thread chats and conversation details
      await loadLeftPaneData();

      // 1. Fetch other user details
      const { data: userData, error: userError } = await supabase
        .from('users')
        .select()
        .eq('id', userId)
        .single();
      
      if (userError) throw userError;
      setOtherUser(userData);

      // 2. Fetch events for @ mentions
      const { data: eventsData } = await supabase
        .from('events')
        .select('id, title')
        .order('date', { ascending: true });
      setAllEvents(eventsData || []);

      // 3. Mark messages as read
      await supabase
        .from('messages')
        .update({ read_at: new Date().toISOString() })
        .eq('sender_id', userId)
        .eq('receiver_id', currentUser.id)
        .is('read_at', null);

      // 4. Fetch messages
      const convId = generateConvId(currentUser.id, userId);
      const { data: msgData, error: msgError } = await supabase
        .from('messages')
        .select()
        .eq('conversation_id', convId)
        .order('timestamp', { ascending: true });

      if (msgError) throw msgError;
      setMessages(msgData || []);
    } catch (e: any) {
      console.error('Error in chat loading:', e);
      setErrorMsg('Failed to load chat conversation.');
    } finally {
      setIsLoading(false);
      scrollToBottom();
    }
  };

  const scrollToBottom = () => {
    setTimeout(() => {
      if (scrollRef.current) {
        scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
      }
    }, 100);
  };

  useEffect(() => {
    loadData();

    if (!currentUser || !userId) return;
    const convId = generateConvId(currentUser.id, userId);

    // Subscribe to messages changes for real-time
    const chatChannel = supabase
      .channel(`chat:${convId}`)
      .on('postgres_changes', { 
        event: '*', 
        schema: 'public', 
        table: 'messages',
        filter: `conversation_id=eq.${convId}` 
      }, (payload: any) => {
        if (payload.eventType === 'INSERT') {
          const newMsg = payload.new;
          setMessages(prev => {
            if (prev.some(m => m.id === newMsg.id)) return prev;
            return [...prev, newMsg];
          });
          
          // Auto mark as read if message is from the other user
          if (newMsg.sender_id === userId) {
            supabase
              .from('messages')
              .update({ read_at: new Date().toISOString() })
              .eq('id', newMsg.id)
              .then();
          }
          scrollToBottom();
          loadLeftPaneData();
        } else if (payload.eventType === 'UPDATE') {
          const updated = payload.new;
          setMessages(prev => prev.map(m => m.id === updated.id ? updated : m));
          loadLeftPaneData();
        }
      })
      .subscribe();

    // Subscribe to presence
    const presenceChannel = supabase.channel(`presence:${userId}`);
    presenceChannel
      .on('presence', { event: 'sync' }, () => {
        const state = presenceChannel.presenceState();
        let found = false;
        for (const id in state) {
          const presences = state[id] as any[];
          if (presences.some(p => p.user_id === userId)) {
            found = true;
            break;
          }
        }
        setIsOtherOnline(found);
      })
      .subscribe(async (status) => {
        if (status === 'SUBSCRIBED') {
          await presenceChannel.track({ user_id: currentUser.id, online_at: new Date().toISOString() });
        }
      });

    return () => {
      supabase.removeChannel(chatChannel);
      supabase.removeChannel(presenceChannel);
    };
  }, [userId, currentUser]);

  if (!currentUser || !userId) return null;

  const handleSendMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!inputVal.trim()) return;

    const text = inputVal.trim();
    setInputVal('');
    setShowEventDropdown(false);

    try {
      const convId = generateConvId(currentUser.id, userId);
      const { error } = await supabase.from('messages').insert({
        sender_id: currentUser.id,
        sender: currentUser.name,
        receiver_id: userId,
        conversation_id: convId,
        content: text,
        timestamp: new Date().toISOString()
      });

      if (error) throw error;
      scrollToBottom();
    } catch (e: any) {
      console.error('Error sending message:', e);
      alert('Failed to send message: ' + e.message);
    }
  };

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value;
    setInputVal(val);

    if (val.includes('@')) {
      const parts = val.split('@');
      const query = parts[parts.length - 1].toLowerCase();
      setMentionQuery(query);
      
      const matched = allEvents.filter(ev => ev.title.toLowerCase().includes(query));
      setFilteredEvents(matched);
      setShowEventDropdown(matched.length > 0);
    } else {
      setShowEventDropdown(false);
    }
  };

  const handleSelectEvent = (eventTitle: string) => {
    const parts = inputVal.split('@');
    parts.pop(); // Remove query string
    const newText = `${parts.join('@')}@${eventTitle} `;
    setInputVal(newText);
    setShowEventDropdown(false);

    // Create automatic database announcement to alert members of the mention
    (async () => {
      try {
        await supabase.from('announcements').insert({
          title: `Event Mentioned: ${eventTitle}`,
          content: `Event "${eventTitle}" was discussed in active chat threads by ${currentUser.name}. Check details!`,
          visibility: 'public',
          created_by: currentUser.id
        });
      } catch (err) {
        console.error('Announcement auto-trigger failed:', err);
      }
    })();
  };

  const handleUnsendMessage = async (msg: any) => {
    if (msg.sender_id !== currentUser.id) return;
    
    // Check 15 min limit
    const minsDiff = (new Date().getTime() - new Date(msg.timestamp).getTime()) / (1000 * 60);
    if (minsDiff > 15) {
      alert('Cannot unsend messages after 15 minutes.');
      return;
    }

    if (!window.confirm('Do you want to unsend this message?')) return;

    try {
      const { error } = await supabase
        .from('messages')
        .update({
          is_deleted: true,
          content: 'Message unsent'
        })
        .eq('id', msg.id);

      if (error) throw error;
    } catch (e: any) {
      alert('Unsend failed: ' + e.message);
    }
  };

  const formatTime = (timeStr?: string) => {
    if (!timeStr) return '';
    return new Date(timeStr).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  };

  const formatMessageTime = (timeStr?: string) => {
    if (!timeStr) return '';
    const date = new Date(timeStr);
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  };

  const renderMessageContent = (msg: any) => {
    if (msg.is_deleted) {
      return <span style={{ fontStyle: 'italic', color: 'var(--text-muted)' }}>🚫 Message unsent</span>;
    }

    const text = msg.content;
    if (!text.includes('@')) return <span>{text}</span>;

    // Highlight mentions
    const words = text.split(/(\s+)/);
    return (
      <span>
        {words.map((word: string, index: number) => {
          if (word.startsWith('@')) {
            const cleanTitle = word.substring(1);
            const exists = allEvents.some(e => e.title.toLowerCase() === cleanTitle.toLowerCase());
            if (exists) {
              return (
                <span 
                  key={index} 
                  style={{ color: 'rgb(22, 192, 122)', fontWeight: 'bold', textDecoration: 'underline', cursor: 'pointer' }}
                  onClick={() => navigate('/events')}
                >
                  {word}
                </span>
              );
            }
          }
          return word;
        })}
      </span>
    );
  };

  const filteredChats = searchQuery.trim() === ''
    ? chats
    : chats.filter(c => c.otherUser?.name?.toLowerCase().includes(searchQuery.toLowerCase()));

  const filteredContacts = searchQuery.trim() === ''
    ? contacts
    : contacts.filter(c => c.name?.toLowerCase().includes(searchQuery.toLowerCase()));

  return (
    <div className="chat-portal-layout">
      {/* Left Pane: Conversations & Contacts List (Only displayed on Desktop) */}
      <div className="chat-split-left">
        <header className="page-header">
          <button onClick={() => navigate('/home')} className="back-button">
            <ArrowLeft size={20} />
          </button>
          <h2 className="page-title">Messages</h2>
          <div style={{ width: '20px' }}></div>
        </header>

        {/* Tabs */}
        <div className="chat-tabs flex-center">
          <button 
            onClick={() => setActiveTab('chats')} 
            className={`chat-tab-btn flex-center ${activeTab === 'chats' ? 'active' : ''}`}
          >
            <MessageSquare size={16} style={{ marginRight: '6px' }} />
            Chats
          </button>
          <button 
            onClick={() => setActiveTab('contacts')} 
            className={`chat-tab-btn flex-center ${activeTab === 'contacts' ? 'active' : ''}`}
          >
            <Users size={16} style={{ marginRight: '6px' }} />
            Contacts
          </button>
        </div>

        {/* Search Bar */}
        <div className="search-bar-wrapper flex-center" style={{ margin: '14px 0' }}>
          <Search size={16} className="search-icon" />
          <input 
            type="text" 
            placeholder={activeTab === 'chats' ? 'Search conversations...' : 'Search contacts...'}
            className="chat-search-input"
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
          />
        </div>

        {/* Live Left Pane Threads */}
        <div className="chat-scrollable-content">
          {activeTab === 'chats' ? (
            filteredChats.length === 0 ? (
              <div className="chat-empty flex-center" style={{ height: '150px', color: 'var(--text-muted)' }}>
                No active chats
              </div>
            ) : (
              <div className="chat-threads-flow">
                {filteredChats.map((chat: any) => {
                  const isActiveChat = chat.otherUserId === userId;
                  const hasUnread = chat.unread_count > 0 && chat.last_message_sender_id !== currentUser.id;
                  
                  return (
                    <div 
                      key={chat.conversation_id} 
                      className={`chat-thread-row flex-center ${isActiveChat ? 'active-thread' : ''}`}
                      onClick={() => navigate(`/chat/${chat.otherUserId}`)}
                    >
                      <div className="avatar-holder flex-center">
                        {chat.otherUser?.name?.[0]?.toUpperCase()}
                      </div>
                      <div className="thread-details">
                        <div className="flex-row-between">
                          <span className="contact-name">{chat.otherUser?.name}</span>
                          <span className={`msg-time ${hasUnread ? 'unread' : ''}`}>
                            {formatMessageTime(chat.last_message_time)}
                          </span>
                        </div>
                        <div className="flex-row-between" style={{ marginTop: '2px' }}>
                          <p className="last-msg-snippet">
                            {chat.is_deleted ? '🚫 Message unsent' : chat.last_message}
                          </p>
                          {hasUnread && (
                            <span className="unread-badge flex-center">
                              {chat.unread_count}
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )
          ) : (
            filteredContacts.length === 0 ? (
              <div className="chat-empty flex-center" style={{ height: '150px', color: 'var(--text-muted)' }}>
                No contacts found
              </div>
            ) : (
              <div className="contacts-flow">
                {filteredContacts.map((contact: any) => {
                  const isActiveContact = contact.id === userId;
                  return (
                    <div 
                      key={contact.id} 
                      className={`contact-row flex-center ${isActiveContact ? 'active-thread' : ''}`}
                      onClick={() => navigate(`/chat/${contact.id}`)}
                    >
                      <div className="avatar-holder flex-center contact">
                        {contact.name?.[0]?.toUpperCase()}
                      </div>
                      <div className="contact-info">
                        <span className="contact-name">{contact.name}</span>
                        <span className="contact-subtitle">{contact.post || contact.role}</span>
                      </div>
                    </div>
                  );
                })}
              </div>
            )
          )}
        </div>
      </div>

      {/* Right Pane: Selected Chat Details */}
      <div className="chat-split-right conversation">
        {/* Header bar */}
        <header className="chat-header flex-center">
          <button onClick={() => navigate('/chat')} className="back-button">
            <ArrowLeft size={20} />
          </button>
          
          <div className="chat-user-avatar flex-center">
            {otherUser?.name?.[0]?.toUpperCase()}
          </div>

          <div className="chat-header-info">
            <span className="user-name">{otherUser?.name || 'User'}</span>
            <span className={`presence-lbl ${isOtherOnline ? 'online' : ''}`}>
              {isOtherOnline ? 'online' : 'offline'}
            </span>
          </div>
        </header>

        {/* Messages Board */}
        <div className="messages-board" ref={scrollRef}>
          {isLoading ? (
            <div className="chat-screen-loading flex-center" style={{ height: '100%' }}>
              <div className="spinner"></div>
            </div>
          ) : messages.length === 0 ? (
            <div className="chat-screen-empty flex-center" style={{ flexDirection: 'column', height: '100%' }}>
              <span style={{ color: 'var(--text-muted)', fontSize: '13px' }}>Start a secure conversation.</span>
            </div>
          ) : (
            <div className="messages-flow">
              {messages.map((msg: any) => {
                const isMine = msg.sender_id === currentUser.id;
                
                return (
                  <div 
                    key={msg.id} 
                    className={`message-bubble-wrapper ${isMine ? 'mine' : 'other'}`}
                    onDoubleClick={() => isMine && !msg.is_deleted && handleUnsendMessage(msg)}
                  >
                    <div 
                      className="bubble-content"
                      style={{
                        backgroundColor: isMine 
                          ? 'rgba(22, 192, 122, 0.16)' 
                          : 'rgba(255,255,255,0.02)',
                        borderColor: isMine
                          ? 'rgba(22, 192, 122, 0.25)'
                          : 'var(--border-light)'
                      }}
                    >
                      <p className="bubble-text">{renderMessageContent(msg)}</p>
                      <div className="bubble-meta flex-center">
                        <span className="time-lbl">{formatTime(msg.timestamp)}</span>
                        {isMine && (
                          <span className="check-marks flex-center" style={{ marginLeft: '4px' }}>
                            {msg.read_at ? (
                              <CheckCheck size={12} style={{ color: 'rgb(22, 192, 122)' }} />
                            ) : (
                              <CheckCheck size={12} style={{ color: 'var(--text-muted)' }} />
                            )}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Mention Dropdown Options list */}
        {showEventDropdown && filteredEvents.length > 0 && (
          <GlassCard className="mentions-dropdown" padding="10px">
            {filteredEvents.map(ev => (
              <button 
                key={ev.id}
                className="mention-opt flex-center"
                onClick={() => handleSelectEvent(ev.title)}
              >
                <Calendar size={14} style={{ marginRight: '8px', color: 'rgb(22, 192, 122)' }} />
                {ev.title}
              </button>
            ))}
          </GlassCard>
        )}

        {/* Input keyboard row */}
        <footer className="chat-input-bar">
          <form onSubmit={handleSendMessage} className="chat-input-form flex-center">
            <div className="input-field-wrapper flex-center">
              <Smile size={20} className="smile-icon" />
              <input 
                type="text" 
                placeholder="Message..." 
                className="chat-keyboard"
                value={inputVal}
                onChange={handleInputChange}
              />
            </div>
            <button type="submit" className="chat-send-btn flex-center">
              <Send size={16} />
            </button>
          </form>
        </footer>
      </div>

      <style>{`
        /* Split-Pane Portal Layout */
        .chat-portal-layout {
          width: 100%;
          display: flex;
          flex-direction: column;
          padding: 16px 20px;
          min-height: 100vh;
          box-sizing: border-box;
        }

        .chat-split-left {
          display: none; /* Hidden on mobile */
        }

        .chat-split-right.conversation {
          width: 100%;
          display: flex;
          flex-direction: column;
          height: calc(100vh - 130px);
          background: var(--bg-secondary);
          border: 1px solid var(--border-light);
          border-radius: 24px;
          overflow: hidden;
          box-shadow: var(--shadow-premium);
          margin-bottom: 70px;
        }

        .chat-scrollable-content {
          flex: 1;
          overflow-y: auto;
        }

        @media (min-width: 1024px) {
          .chat-portal-layout {
            display: flex;
            flex-direction: row;
            height: calc(100vh - 40px);
            gap: 24px;
            padding-bottom: 20px;
          }

          .chat-split-left {
            width: 380px;
            flex-shrink: 0;
            display: flex;
            flex-direction: column;
            background: var(--bg-secondary);
            border: 1px solid var(--border-light);
            border-radius: 24px;
            padding: 24px;
            overflow: hidden;
            box-shadow: var(--shadow-premium);
          }

          .chat-split-right.conversation {
            display: flex;
            flex: 1;
            margin-bottom: 0;
            height: 100%;
          }

          .chat-scrollable-content {
            margin-top: 10px;
            padding-right: 4px;
          }

          .chat-split-right.conversation .back-button {
            display: none; /* Hide back button on desktop split view */
          }
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
          flex-shrink: 0;
        }

        .back-button {
          color: var(--text-primary);
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        /* Tabs styling */
        .chat-tabs {
          background: rgba(255,255,255,0.03);
          border: 1px solid var(--border-light);
          padding: 4px;
          border-radius: 12px;
          margin-top: 10px;
          flex-shrink: 0;
        }

        .chat-tab-btn {
          flex: 1;
          padding: 10px;
          border: none;
          background: transparent;
          border-radius: 8px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          color: var(--text-muted);
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .chat-tab-btn.active {
          background: rgba(22, 192, 122, 0.15);
          color: rgb(22, 192, 122);
        }

        /* Search bar */
        .search-bar-wrapper {
          background: rgba(255,255,255,0.02);
          border: 1px solid var(--border-light);
          border-radius: 12px;
          padding: 10px 16px;
          width: 100%;
          flex-shrink: 0;
        }

        .search-icon {
          color: var(--text-muted);
          margin-right: 10px;
        }

        .chat-search-input {
          background: transparent;
          border: none;
          outline: none;
          color: var(--text-primary);
          font-family: var(--font-inter);
          font-size: 13.5px;
          width: 100%;
        }

        /* Threads list */
        .chat-threads-flow, .contacts-flow {
          display: flex;
          flex-direction: column;
          gap: 8px;
          margin-top: 6px;
        }

        .chat-thread-row, .contact-row {
          padding: 14px;
          border-radius: 16px;
          background: rgba(255,255,255,0.015);
          border: 1px solid var(--border-light);
          cursor: pointer;
          transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
          justify-content: flex-start;
        }

        .chat-thread-row:hover, .contact-row:hover {
          background: rgba(255,255,255,0.04);
          transform: translateY(-2px);
          box-shadow: 0 4px 15px rgba(0,0,0,0.03);
        }

        .chat-thread-row.active-thread, .contact-row.active-thread {
          background: rgba(22, 192, 122, 0.08);
          border-color: rgba(22, 192, 122, 0.3);
        }

        .avatar-holder {
          width: 46px;
          height: 46px;
          border-radius: 50%;
          background: rgba(22, 192, 122, 0.12);
          color: rgb(22, 192, 122);
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 18px;
          flex-shrink: 0;
        }

        .avatar-holder.contact {
          background: rgba(255,255,255,0.04);
          color: var(--text-secondary);
        }

        .thread-details {
          flex: 1;
          margin-left: 14px;
          display: flex;
          flex-direction: column;
        }

        .contact-info {
          margin-left: 14px;
          display: flex;
          flex-direction: column;
          gap: 2px;
        }

        .contact-name {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 15px;
          color: var(--text-primary);
        }

        .flex-row-between {
          display: flex;
          justify-content: space-between;
          align-items: center;
          width: 100%;
        }

        .msg-time {
          font-size: 11px;
          color: var(--text-muted);
        }

        .msg-time.unread {
          color: rgb(22, 192, 122);
          font-weight: 700;
        }

        .last-msg-snippet {
          font-size: 13px;
          color: var(--text-secondary);
          margin: 0;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 160px;
        }

        .unread-badge {
          background: rgb(22, 192, 122);
          color: #fff;
          border-radius: 50%;
          width: 18px;
          height: 18px;
          font-size: 9.5px;
          font-weight: 800;
          flex-shrink: 0;
        }

        .contact-subtitle {
          font-size: 12.5px;
          color: var(--text-muted);
        }

        /* Message board pane details */
        .chat-header {
          height: 60px;
          padding: 0 16px;
          border-bottom: 1px solid var(--border-light);
          background: var(--bg-secondary);
          backdrop-filter: blur(10px);
          justify-content: flex-start;
          flex-shrink: 0;
          z-index: 10;
        }

        .chat-user-avatar {
          width: 38px;
          height: 38px;
          border-radius: 50%;
          background: rgba(22, 192, 122, 0.12);
          color: rgb(22, 192, 122);
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 16px;
          flex-shrink: 0;
          margin-left: 8px;
        }

        .chat-header-info {
          display: flex;
          flex-direction: column;
          margin-left: 12px;
        }

        .user-name {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 15px;
          color: var(--text-primary);
        }

        .presence-lbl {
          font-size: 11px;
          color: var(--text-muted);
        }

        .presence-lbl.online {
          color: rgb(22, 192, 122);
          font-weight: 700;
        }

        .messages-board {
          flex: 1;
          overflow-y: auto;
          padding: 20px;
          display: flex;
          flex-direction: column;
          background: radial-gradient(circle at bottom, rgba(22, 192, 122, 0.01) 0%, transparent 60%);
        }

        .messages-flow {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }

        .message-bubble-wrapper {
          display: flex;
          width: 100%;
        }

        .message-bubble-wrapper.mine {
          justify-content: flex-end;
        }

        .message-bubble-wrapper.other {
          justify-content: flex-start;
        }

        .bubble-content {
          max-width: 75%;
          padding: 10px 14px;
          border-radius: 16px;
          border: 1px solid;
          display: flex;
          flex-direction: column;
          gap: 4px;
          box-shadow: 0 2px 8px rgba(0,0,0,0.02);
        }

        .message-bubble-wrapper.mine .bubble-content {
          border-radius: 16px 16px 0 16px;
        }

        .message-bubble-wrapper.other .bubble-content {
          border-radius: 16px 16px 16px 0;
        }

        .bubble-text {
          font-size: 14.5px;
          color: var(--text-primary);
          margin: 0;
          line-height: 1.45;
          word-break: break-word;
        }

        .bubble-meta {
          justify-content: flex-end;
          align-self: flex-end;
        }

        .time-lbl {
          font-size: 9.5px;
          color: var(--text-muted);
        }

        /* Mentions dropdown options list */
        .mentions-dropdown {
          position: absolute;
          bottom: 74px;
          left: 20px;
          right: 20px;
          max-height: 180px;
          overflow-y: auto;
          z-index: 100;
          box-shadow: var(--shadow-premium);
          border: 1px solid var(--border-glass);
        }

        .mention-opt {
          width: 100%;
          padding: 11px 14px;
          background: rgba(255,255,255,0.01);
          border: none;
          border-bottom: 1px solid var(--border-light);
          text-align: left;
          color: var(--text-primary);
          font-family: var(--font-inter);
          font-size: 13.5px;
          cursor: pointer;
          justify-content: flex-start;
        }

        .mention-opt:last-child {
          border-bottom: none;
        }

        .mention-opt:hover {
          background: rgba(255,255,255,0.04);
        }

        /* Keyboard Input Bar */
        .chat-input-bar {
          padding: 12px 20px 24px 20px;
          background: var(--bg-secondary);
          border-top: 1px solid var(--border-light);
          flex-shrink: 0;
        }

        .chat-input-form {
          width: 100%;
        }

        .input-field-wrapper {
          flex: 1;
          background: rgba(255, 255, 255, 0.02);
          border: 1px solid var(--border-light);
          border-radius: 20px;
          padding: 8px 16px;
        }

        .smile-icon {
          color: var(--text-muted);
          margin-right: 12px;
          flex-shrink: 0;
        }

        .chat-keyboard {
          background: transparent;
          border: none;
          outline: none;
          color: var(--text-primary);
          font-family: var(--font-inter);
          font-size: 14px;
          width: 100%;
          padding: 6px 0;
        }

        .chat-send-btn {
          width: 44px;
          height: 44px;
          background: rgb(22, 192, 122);
          color: #fff;
          border-radius: 16px;
          border: none;
          cursor: pointer;
          margin-left: 12px;
          flex-shrink: 0;
          box-shadow: 0 4px 12px rgba(22, 192, 122, 0.2);
          transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
        }

        .chat-send-btn:hover {
          transform: translateY(-1px);
          box-shadow: 0 6px 15px rgba(22, 192, 122, 0.3);
        }

        .spinner {
          width: 24px;
          height: 24px;
          border: 3px solid rgba(255,255,255,0.06);
          border-radius: 50%;
          border-top-color: rgb(22, 192, 122);
          animation: spin 0.8s linear infinite;
        }

        @keyframes spin {
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
};
