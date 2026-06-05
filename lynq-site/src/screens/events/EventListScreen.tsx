import React, { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ArrowLeft, Calendar as CalendarIcon, Plus, MapPin, Trash, Loader, Clock, Image as ImageIcon } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { AppRole, appRoleFromString } from '../../core/constants';
import { EventModel } from '../../models/types';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';
import { CalendarWidget, EventsData } from '../../shared/components/CalendarWidget';

export const EventListScreen: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { currentUser, permissions } = useAuth();
  const folderParam = searchParams.get('folder');
  const folderId = folderParam ? parseInt(folderParam) : null;

  const [events, setEvents] = useState<EventModel[]>([]);
  const [creatorRoles, setCreatorRoles] = useState<Record<string, string>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [selectedDate, setSelectedDate] = useState<string>(new Date().toISOString().split('T')[0]);

  const loadEvents = async () => {
    setIsLoading(true);
    try {
      let query = supabase.from('events').select('*, folder_id:execom_id');
      if (folderId) {
        query = query.eq('execom_id', folderId);
      }

      const { data: eventsData, error: eError } = await query
        .order('date', { ascending: false })
        .limit(100);

      if (eError) throw eError;

      const loadedEvents = (eventsData || []) as EventModel[];
      setEvents(loadedEvents);

      // Load creator roles to resolve hierarchy
      const userIds = Array.from(new Set(loadedEvents.map((e) => e.created_by).filter((id) => id)));
      if (userIds.length > 0) {
        const { data: usersData, error: uError } = await supabase
          .from('users')
          .select('id, role')
          .in('id', userIds);

        if (!uError && usersData) {
          const rolesMap: Record<string, string> = {};
          usersData.forEach((u) => {
            rolesMap[u.id] = u.role;
          });
          setCreatorRoles(rolesMap);
        }
      }
    } catch (e) {
      console.error('Error fetching events:', e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadEvents();
  }, [folderId]);

  const canDeleteEvent = (event: EventModel) => {
    if (!permissions || !currentUser) return false;
    if (permissions.isEffectivelyTier1) return true;
    if (event.created_by === currentUser.id) return true;

    if (event.created_by) {
      const creatorRoleStr = creatorRoles[event.created_by];
      if (creatorRoleStr) {
        const creatorRole = appRoleFromString(creatorRoleStr);
        if (permissions.role > creatorRole) return true;
      }
    }
    return false;
  };

  const handleDeleteEvent = async (event: EventModel, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!window.confirm(`Are you sure you want to delete the event: "${event.title}"?`)) return;

    try {
      const { error } = await supabase.from('events').delete().eq('id', event.id);
      if (error) throw error;
      setEvents(events.filter((ev) => ev.id !== event.id));
      alert('Event deleted successfully!');
    } catch (err) {
      console.error('Delete event error:', err);
      alert('Failed to delete event');
    }
  };

  if (!currentUser || !permissions) return null;

  // Filter events matching selected date
  const filteredEvents = events.filter((e) => e.date === selectedDate);
  const canAdd = permissions.isAtLeastTier2 || (folderId && permissions.canDoInFolder(folderId, 'create_events'));

  // Map events to the calendar expected structure
  const mappedEventsData: EventsData = {};
  events.forEach((evt) => {
    if (evt.date) {
      if (!mappedEventsData[evt.date]) {
        mappedEventsData[evt.date] = [];
      }
      mappedEventsData[evt.date].push(evt);
    }
  });

  return (
    <div className="event-list-container">
      <header className="page-header">
        <button onClick={() => navigate(folderId ? `/folders/${folderId}` : '/home')} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title">Upcoming Events</h2>
        {canAdd ? (
          <button 
            onClick={() => navigate(`/events/create${folderId ? `?folder=${folderId}` : ''}`)} 
            className="create-event-btn"
          >
            <Plus size={20} />
          </button>
        ) : (
          <div style={{ width: '20px' }}></div>
        )}
      </header>

      {/* Dynamic Animated Swipeable Calendar Filter */}
      <CalendarWidget
        events={mappedEventsData}
        selectedDate={selectedDate}
        onDateSelect={(date) => setSelectedDate(date)}
      />

      {/* Events Flow Listing */}
      {isLoading ? (
        <div className="events-loading flex-center" style={{ height: '200px' }}>
          <Loader size={24} className="spinner" />
        </div>
      ) : filteredEvents.length === 0 ? (
        <div className="events-empty flex-center" style={{ flexDirection: 'column', height: '200px' }}>
          <CalendarIcon size={44} style={{ color: 'var(--text-muted)', marginBottom: '12px' }} />
          <span>No events on this day.</span>
        </div>
      ) : (
        <div className="events-list-flow" style={{ marginBottom: '40px' }}>
          {filteredEvents.map((event) => {
            return (
              <GlassCard key={event.id} className="event-item-card" padding="20px">
                {event.poster_url && (
                  <div className="event-poster-wrapper">
                    <img src={event.poster_url} alt={event.title} className="event-poster-img" />
                  </div>
                )}
                
                <div className="event-type-row">
                  <span className="event-type-badge">{event.type?.toUpperCase() || 'EVENT'}</span>
                  <div className="event-time flex-center">
                    <Clock size={13} style={{ marginRight: '4px' }} />
                    <span>{event.date}</span>
                  </div>
                </div>

                <h3 className="event-item-title">{event.title}</h3>
                {event.description && <p className="event-item-desc">{event.description}</p>}
                
                <div className="event-item-meta flex-center" style={{ justifyContent: 'space-between', marginTop: '16px' }}>
                  {event.location && (
                    <div className="meta-loc flex-center">
                      <MapPin size={14} style={{ color: 'var(--text-muted)', marginRight: '4px' }} />
                      <span>{event.location}</span>
                    </div>
                  )}
                  {event.is_paid && (
                    <span className="price-tag">₹{event.member_price} / ₹{event.non_member_price}</span>
                  )}
                </div>

                {canDeleteEvent(event) && (
                  <button onClick={(e) => handleDeleteEvent(event, e)} className="event-delete-card-btn flex-center">
                    <Trash size={16} style={{ marginRight: '6px' }} /> Delete Event
                  </button>
                )}
              </GlassCard>
            );
          })}
        </div>
      )}

      <NavBar />

      <style>{`
        .event-list-container {
          padding: 16px 20px;
        }

        .page-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: 60px;
          margin-bottom: 20px;
        }

        .back-button, .create-event-btn {
          color: var(--text-primary);
        }

        .page-title {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 20px;
          color: var(--text-primary);
        }

        .date-filter-section {
          background: rgba(255, 255, 255, 0.04);
          border: 1px solid var(--border-light);
          border-radius: 14px;
          padding: 10px 16px;
          margin-bottom: 20px;
          width: 100%;
        }

        .calendar-date-input {
          border: none;
          background: transparent;
          color: var(--text-primary);
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 14px;
          outline: none;
          padding: 0;
          cursor: pointer;
        }

        .calendar-date-input::-webkit-calendar-picker-indicator {
          filter: invert(1);
        }

        .events-loading, .events-empty {
          text-align: center;
          color: var(--text-secondary);
        }

        .events-list-flow {
          display: flex;
          flex-direction: column;
          gap: 16px;
        }

        @media (min-width: 768px) {
          .events-list-flow {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
            gap: 20px;
          }
        }

        .event-item-card {
          width: 100%;
        }

        .event-poster-wrapper {
          width: 100%;
          height: 150px;
          border-radius: 12px;
          overflow: hidden;
          background: rgba(0,0,0,0.1);
          margin-bottom: 16px;
        }

        .event-poster-img {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }

        .event-type-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 12px;
          width: 100%;
        }

        .event-type-badge {
          background: rgba(22, 192, 122, 0.1);
          color: rgb(22, 192, 122);
          border: 1px solid rgba(22, 192, 122, 0.3);
          border-radius: 8px;
          padding: 4px 10px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 10px;
          letter-spacing: 0.5px;
        }

        .event-time {
          font-size: 12px;
          color: var(--text-muted);
        }

        .event-item-title {
          font-size: 18px;
          font-weight: 700;
          color: var(--text-primary);
          margin-bottom: 6px;
        }

        .event-item-desc {
          font-size: 13px;
          color: var(--text-secondary);
          line-height: 1.5;
        }

        .event-item-meta {
          font-size: 12px;
          color: var(--text-muted);
        }

        .price-tag {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          color: rgb(22, 192, 122);
          background: rgba(22, 192, 122, 0.1);
          border-radius: 6px;
          padding: 3px 8px;
        }

        .event-delete-card-btn {
          margin-top: 18px;
          width: 100%;
          padding: 10px;
          border: 1px dashed rgba(239, 68, 68, 0.3);
          background: rgba(239, 68, 68, 0.05);
          color: rgb(239, 68, 68);
          border-radius: 12px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13px;
          transition: all 0.2s ease;
        }

        .event-delete-card-btn:hover {
          background: rgba(239, 68, 68, 0.12);
        }

        .spinner {
          animation: spin 1s linear infinite;
        }

        @keyframes spin {
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
};
